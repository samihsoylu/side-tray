import AppKit
import Sparkle

// Sparkle owns archive extraction, bundle validation, replacement and relaunch.
// Its install-on-quit mode is deliberately disabled. Before consent, we use only
// an information probe and an inert, signature-verified download.
final class UpdateInstallDriver:SPUStandardUserDriver {
 var approvedBuild:String?
 override func showUpdateFound(with appcastItem:SUAppcastItem,state:SPUUserUpdateState,reply:@escaping (SPUUserUpdateChoice)->Void) {
  guard approvedBuild == appcastItem.versionString,!appcastItem.isInformationOnlyUpdate else { reply(.dismiss); return }
  reply(.install)
 }
 override func showReady(toInstallAndRelaunch reply:@escaping (SPUUserUpdateChoice)->Void) {
  reply(approvedBuild == nil ? .skip : .install)
 }
}

final class Updates:NSObject,SPUUpdaterDelegate,URLSessionDownloadDelegate {
 static let repository="samihsoylu/side-tray"
 #if SIDETRAY_UPDATE_FIXTURE
 static let publicKey=Bundle.main.object(forInfoDictionaryKey:"SUPublicEDKey") as! String
 #else
 static let publicKey="r7UuuKkGu2L7nTKNXnACxbidTszFTK5hkGmAygh0tS0="
 #endif
 var changed:(()->Void)?
 private(set) var message="Updates are checked daily. Installation always waits for you."
 private(set) var busy=false
 private(set) var installing=false
 private(set) var candidate:UpdateCandidate?
 private var proposed:UpdateCandidate?
 private var cachedArchive:URL?
 private var timer:Timer?
 private var download:URLSessionDownloadTask?
 private var session:URLSession?
 private var updater:SPUUpdater?
 private let driver=UpdateInstallDriver(hostBundle:.main,delegate:nil)
 private var sawCandidate=false
 private var cacheDirectory:URL {
  FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("\(Bundle.main.bundleIdentifier ?? "io.sidetray.prototype")/Updates",isDirectory:true)
 }
 var automatic:Bool {
  get { UserDefaults.standard.object(forKey:"SideTrayAutomaticUpdateChecks") as? Bool ?? true }
  set { UserDefaults.standard.set(newValue,forKey:"SideTrayAutomaticUpdateChecks"); changed?() }
 }
 func start() {
  #if !SIDETRAY_UPDATE_FIXTURE
  guard Bundle.main.bundleIdentifier == "io.sidetray.prototype" else { return }
  #endif
  let service=SPUUpdater(hostBundle:.main,applicationBundle:.main,userDriver:driver,delegate:self)
  updater=service
  do { try service.start() }
  catch { message="Updates could not start. \(error.localizedDescription)"; changed?(); return }
  restoreDownload()
  timer=Timer.scheduledTimer(withTimeInterval:3600,repeats:true) { [weak self] _ in self?.scheduledCheck() }
  scheduledCheck()
 }
 private func scheduledCheck() {
  let last=UserDefaults.standard.object(forKey:"SideTrayLastUpdateAttempt") as? Date ?? .distantPast
  if automatic && Date().timeIntervalSince(last) >= 86400 { check() }
 }
 func check() {
  guard !busy,!installing,candidate == nil,let updater else { return }
  guard supportedInstallation else { message=UpdateFailure.unsupported.localizedDescription; changed?(); return }
  sawCandidate=false; busy=true
  message="Checking for updates…"; changed?()
  UserDefaults.standard.set(Date(),forKey:"SideTrayLastUpdateAttempt")
  updater.checkForUpdateInformation()
 }
 private var supportedInstallation:Bool {
  #if SIDETRAY_UPDATE_FIXTURE
  return true
  #else
  return ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27 && Bundle.main.bundleURL.deletingLastPathComponent().path == "/Applications"
  #endif
 }
 private func restoreDownload() {
  do {
   let manifest=cacheDirectory.appendingPathComponent("download.json")
   let archive=cacheDirectory.appendingPathComponent("update.zip")
   let metadataSize=try FileManager.default.attributesOfItem(atPath:manifest.path)[.size] as? NSNumber
   guard (metadataSize?.intValue ?? 0) < 16384 else { throw UpdateFailure.invalidRelease }
   let saved=try JSONDecoder().decode(UpdateCandidate.self,from:Data(contentsOf:manifest))
   let restored=try UpdateCandidate(build:saved.build,version:saved.version,url:saved.url,length:saved.length,signature:saved.signature.base64EncodedString(),repository:Self.repository)
   let current=Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "0"
   let size=try FileManager.default.attributesOfItem(atPath:archive.path)[.size] as? NSNumber
   guard restored.build.compare(current,options:.numeric) == .orderedDescending,size?.uint64Value == restored.length else { throw UpdateFailure.invalidRelease }
   try restored.verify(Data(contentsOf:archive,options:.mappedIfSafe),publicKey:Self.publicKey)
   candidate=restored; cachedArchive=archive; message="SideTray \(restored.version) is downloaded and ready. Installation waits for you."; changed?()
  } catch {
   // Only inert prefetch files belonging to this app; not Sparkle installer state.
   try? FileManager.default.removeItem(at:cacheDirectory)
  }
 }
 func install() {
  guard !busy,!installing,let candidate,let archive=cachedArchive,let updater else { return }
  guard supportedInstallation else { fail(UpdateFailure.unsupported); return }
  do {
   let size=try FileManager.default.attributesOfItem(atPath:archive.path)[.size] as? NSNumber
   guard size?.uint64Value == candidate.length else { throw UpdateFailure.invalidSignature }
   try candidate.verify(Data(contentsOf:archive,options:.mappedIfSafe),publicKey:Self.publicKey)
  }
  catch { fail(error); return }
  // Only this explicit action authorizes Sparkle to begin an installation.
  installing=true; driver.approvedBuild=candidate.build
  message="Preparing to install \(candidate.version)…"; changed?()
  updater.checkForUpdates()
 }
 func cancelDownload() {
  download?.cancel(); download=nil; session?.invalidateAndCancel(); session=nil
  proposed=nil; busy=false; message="Download cancelled. Check again whenever you’re ready."; changed?()
 }
 func updater(_ updater:SPUUpdater,shouldProceedWithUpdate item:SUAppcastItem,updateCheck:SPUUpdateCheck) throws {
  let next=try makeCandidate(item)
  if updateCheck != .updateInformation {
   guard installing,let candidate,candidate == next,driver.approvedBuild == next.build else { throw UpdateFailure.releaseChanged }
  }
 }
 func updater(_ updater:SPUUpdater,didFindValidUpdate item:SUAppcastItem) {
  guard !installing else { return }
  do {
   let next=try makeCandidate(item); sawCandidate=true; proposed=next
   message="Downloading SideTray \(next.version)…"; changed?()
   let configuration=URLSessionConfiguration.ephemeral
   configuration.timeoutIntervalForRequest=30; configuration.timeoutIntervalForResource=600
   configuration.httpCookieStorage=nil; configuration.urlCredentialStorage=nil
   let connection=URLSession(configuration:configuration,delegate:self,delegateQueue:.main); session=connection
   let task=connection.downloadTask(with:next.url); download=task; task.resume()
  } catch { fail(error) }
 }
 private func makeCandidate(_ item:SUAppcastItem) throws -> UpdateCandidate {
  guard !item.isInformationOnlyUpdate,let url=item.fileURL,
        let enclosure=item.propertiesDictionary["enclosure"] as? [String:Any],
        let signature=enclosure["sparkle:edSignature"] as? String else { throw UpdateFailure.invalidRelease }
  return try UpdateCandidate(build:item.versionString,version:item.displayVersionString,url:url,length:item.contentLength,signature:signature,repository:Self.repository)
 }
 func updater(_ updater:SPUUpdater,didFinishUpdateCycleFor updateCheck:SPUUpdateCheck,error:Error?) {
  if installing {
   installing=false; driver.approvedBuild=nil
   if let error { fail(error) }
   else { message="Update installation ended. Check again to retry."; changed?() }
  } else if !sawCandidate {
   busy=false
   // A missing feed is a connection/publication error, never “up to date”.
   if let error,error._code != SUError.noUpdateError.rawValue { message="Could not check for updates. Try again later." }
   else {
    let reason=(error as NSError?)?.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber
    switch reason?.int32Value {
    case SPUNoUpdateFoundReason.onLatestVersion.rawValue,SPUNoUpdateFoundReason.onNewerThanLatestVersion.rawValue:
     message="You’re up to date."
    case SPUNoUpdateFoundReason.systemIsTooOld.rawValue,SPUNoUpdateFoundReason.systemIsTooNew.rawValue,SPUNoUpdateFoundReason.hardwareDoesNotSupportARM64.rawValue:
     message="No newer update is compatible with this Mac."
    default: message="No updates are published for this version yet."
    }
   }
   changed?()
  }
 }
 func allowedChannels(for updater:SPUUpdater)->Set<String> { ["beta"] }
 func updater(_ updater:SPUUpdater,shouldDownloadReleaseNotesForUpdate updateItem:SUAppcastItem)->Bool { false }
 func updater(_ updater:SPUUpdater,willDownloadUpdate item:SUAppcastItem,with request:NSMutableURLRequest) {
  // A prefetched response can avoid a second transfer where URLSession permits.
  // Sparkle still verifies the archive independently before extracting it.
  request.cachePolicy = .returnCacheDataElseLoad
 }
 func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didWriteData bytesWritten:Int64,totalBytesWritten:Int64,totalBytesExpectedToWrite:Int64) {
  if totalBytesWritten > Int64(UpdateCandidate.maximumBytes) || totalBytesExpectedToWrite > Int64(UpdateCandidate.maximumBytes) { downloadTask.cancel() }
 }
 func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping (URLRequest?)->Void) {
  let allowed=["github.com","release-assets.githubusercontent.com","objects.githubusercontent.com"]
  guard let url=request.url,url.scheme == "https",allowed.contains(url.host ?? ""),url.user == nil,url.password == nil else { completionHandler(nil); return }
  completionHandler(request)
 }
 func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didFinishDownloadingTo location:URL) {
  guard self.download === downloadTask,let next=proposed else { return }
  do {
   guard let response=downloadTask.response as? HTTPURLResponse,response.statusCode == 200 else { throw UpdateFailure.download }
   let size=try FileManager.default.attributesOfItem(atPath:location.path)[.size] as? NSNumber
   guard size?.uint64Value == next.length else { throw UpdateFailure.invalidSignature }
   let data=try Data(contentsOf:location,options:.mappedIfSafe)
   try next.verify(data,publicKey:Self.publicKey)
   try FileManager.default.createDirectory(at:cacheDirectory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
   let archive=cacheDirectory.appendingPathComponent("update.zip")
   try data.write(to:archive,options:.atomic)
   try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:archive.path)
   if let response=HTTPURLResponse(url:next.url,statusCode:200,httpVersion:"HTTP/1.1",headerFields:["Content-Type":"application/zip","Cache-Control":"max-age=86400"]) {
    URLCache.shared.storeCachedResponse(CachedURLResponse(response:response,data:data),for:URLRequest(url:next.url))
   }
   let manifest=cacheDirectory.appendingPathComponent("download.json")
   try JSONEncoder().encode(next).write(to:manifest,options:.atomic)
   try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:manifest.path)
   candidate=next; cachedArchive=archive; proposed=nil; busy=false
   message="SideTray \(next.version) is downloaded and ready. macOS may ask to renew permissions after this update."; changed?()
  } catch { fail(error) }
 }
 func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?) {
  guard download === task else { return }
  download=nil; session.finishTasksAndInvalidate(); self.session=nil
  if let error,proposed != nil { fail(error) }
 }
 private func fail(_ error:Error) {
  busy=false; proposed=nil; candidate=nil; cachedArchive=nil
  try? FileManager.default.removeItem(at:cacheDirectory)
  message=(error as? UpdateFailure)?.localizedDescription ?? "The update could not be completed. Your installed app is unchanged; try again."
  changed?()
 }
}
