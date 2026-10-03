# Adds "Take Photo with <phone>" to the Files right-click menu, one item per phone
# set up with phone-setup. Opens that phone's camera and saves the new photo into
# the current (or selected) folder.
import glob
import os
import shlex
import subprocess
from urllib.parse import unquote, urlparse

from gi.repository import GObject, Nautilus

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


class PhonePhotoExtension(GObject.GObject, Nautilus.MenuProvider):
    def _items(self, kind, folder):
        items = []
        for name in _phone_names():
            item = Nautilus.MenuItem(name=f"PhonePhoto::{kind}::{name}",
                                     label=f"Take Photo with {name}")
            item.connect("activate",
                         lambda _i, n=name: subprocess.Popen([SCRIPT, "--phone", n, folder]))
            items.append(item)
        return items

    def get_background_items(self, current_folder):
        if current_folder.get_uri_scheme() != "file":
            return []
        return self._items("Background", _path(current_folder))

    def get_file_items(self, files):
        if len(files) != 1 or not files[0].is_directory() or files[0].get_uri_scheme() != "file":
            return []
        return self._items("Folder", _path(files[0]))
