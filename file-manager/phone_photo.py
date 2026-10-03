# Adds "Take Photo with <phone>" to the file manager's right-click menu, one item per
# phone set up with phone-setup. Opens that phone's camera and saves the new photo into
# the current (or selected) folder.
# Works in GNOME Files (nautilus-python) and Nemo (nemo-python); Nemo passes an extra
# window argument to the menu callbacks, hence the *args.
import glob
import os
import shlex
import subprocess
from urllib.parse import unquote, urlparse

import gi
from gi.repository import GObject

# Use whichever file manager loaded this extension
if "Nemo" in gi.Repository.get_default().get_loaded_namespaces():
    from gi.repository import Nemo as FileManager
else:
    from gi.repository import Nautilus as FileManager

SCRIPT = os.path.expanduser("~/.local/bin/phone-photo")
DEVICES = os.path.expanduser("~/.config/phone-continuity/devices/*.conf")


def _path(file_info):
    return unquote(urlparse(file_info.get_uri()).path)


def _phone_names():
    names = []
    for conf in sorted(glob.glob(DEVICES)):
        with open(conf) as f:
            for line in f:
                if line.startswith("NAME="):
                    names.append(shlex.split(line.strip()[5:])[0])
    return names


class PhonePhotoExtension(GObject.GObject, FileManager.MenuProvider):
    def _items(self, kind, folder):
        items = []
        for name in _phone_names():
            item = FileManager.MenuItem(name=f"PhonePhoto::{kind}::{name}",
                                        label=f"Take Photo with {name}")
            item.connect("activate",
                         lambda _i, n=name: subprocess.Popen([SCRIPT, "--phone", n, folder]))
            items.append(item)
        return items

    def get_background_items(self, *args):
        current_folder = args[-1]
        if current_folder.get_uri_scheme() != "file":
            return []
        return self._items("Background", _path(current_folder))

    def get_file_items(self, *args):
        files = args[-1]
        if len(files) != 1 or not files[0].is_directory() or files[0].get_uri_scheme() != "file":
            return []
        return self._items("Folder", _path(files[0]))
