#!/usr/bin/env python

import yaml
import sys
import itertools

def is_bundle(blob):
    return blob.get("schema", "") == "olm.bundle"

def is_channel(prop):
    return prop.get("type", "") == "olm.channel"

def prop_value(prop):
    return prop.get("value")

def get_channels(bundle):
    props = filter(lambda p: is_channel(p), bundle.get("properties", []))
    return (prop_value(prop) for prop in props)

def get_names(channels):
    return set(ch.get("name") for ch in channels)

def get_replaces(channels):
    return set(ch.get("replaces") for ch in channels)

def descendents(map, self):
    desc = []
    for (name, v) in map.items():
        if v.get("replaces") == self:
            desc.append(name)
    for d in desc:
        desc.extend(descendents(map,d))
    return set(desc)

blobs = []
with open(sys.argv[1]) as f:
    blobs = list(yaml.load_all(f, Loader=yaml.FullLoader))

map = {}
bundles = (b for b in blobs if is_bundle(b))
for b in bundles:
    name = b.get("name")
    package = b.get("package")
    channels = get_channels(b)
    ch1, ch2 = itertools.tee(channels, 2)
    replaces = get_replaces(ch1)
    if len(replaces) > 1:
        sys.exit('package "{}" bundle "{}" contains {} replaces, but max of 1 is allowed'.format(package, name, len(replaces)))
    map[name] = {"bundle": b, "channels": get_names(ch2), "replaces": next(iter(replaces), None)}

props = {}
for (name,b) in map.items():
    replaces = b.get("replaces")
    channels = b.get("channels")

    desc_channels = set()
    desc = descendents(map, name)
    for d in desc:
        desc_channels.update(map.get(d).get("channels"))

    chprops = []
    for ch in (desc_channels - channels):
        if replaces:
            chprops.append({"type": "olm.channel", "value":{"name":ch, "replaces": replaces}})
        else:
            chprops.append({"type": "olm.channel", "value":{"name":ch}})

    props[name] = chprops

def by_value(prop):
    return prop.get("value").get("name")

for b in blobs:
    if is_bundle(b):
        name = b.get("name")
        chprops = props[name]
        if chprops:
            b.get("properties").extend(sorted(chprops, key=lambda p: p.get("value").get("name")))

with open(sys.argv[1], "w") as f:
    yaml.dump_all(blobs, f, explicit_start=True)
