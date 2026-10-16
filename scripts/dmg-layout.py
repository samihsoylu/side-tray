"""Write a portable Finder layout; no local paths or user preferences are copied."""
import pathlib, sys
from ds_store import DSStore
root = pathlib.Path(sys.argv[1])
with DSStore.open(str(root / '.DS_Store'), 'w+') as store:
    store['.']['bwsp'] = {'ShowToolbar': False, 'ShowStatusBar': False,
        'ShowSidebar': False, 'ShowTabView': False, 'ShowPathbar': False,
        'WindowBounds': '{{200, 160}, {540, 420}}'}
    store['.']['vSrn'] = ('long', 1)
    store['.']['vstl'] = ('type', b'icnv')
    store['.']['icvp'] = {'viewOptionsVersion': 1, 'backgroundType': 0,
        'iconSize': 96.0, 'textSize': 14.0, 'labelOnBottom': True,
        'arrangeBy': 'none', 'gridSpacing': 100.0, 'gridOffsetX': 0.0,
        'gridOffsetY': 0.0, 'showIconPreview': True, 'showItemInfo': False}
    store['SideTray.app']['Iloc'] = (140, 110)
    store['Applications']['Iloc'] = (400, 110)
    store['Install and Open.txt']['Iloc'] = (270, 220)
