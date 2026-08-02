#!/usr/bin/env python3
"""Generate and verify the KenshiCoop x2/x3 data-only game starts."""

from __future__ import annotations

import argparse
import copy
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CANONICAL = ROOT / "dist" / "mods" / "KenshiCoop" / "KenshiCoop.mod"
PACKAGED = ROOT / "dist" / "mod-kit" / "KenshiCoop" / "KenshiCoop.mod"
MOD_SUFFIX = "-KenshiCoop-MultiplayerStart.mod"
GENERATED_IDS = {f"{number}{MOD_SUFFIX}" for number in (4, 5, 6)}
HEADER_DESCRIPTION = (
    "Multiplayer game starts for KenshiCoop. Includes Wanderer x2 and Wanderer x3, "
    "with one wanderer in each squad tab so every connected player has a distinct "
    "starting squad. Data-only mod; requires the KenshiCoop plugin for co-op."
)
X3_DESCRIPTION = (
    "Three lone wanderers with nothing but a few coins, a pair of pants each and "
    "a rusty sword each, ready to venture out into the world together. Designed "
    "for KenshiCoop: each wanderer starts in their own squad, so the host controls "
    "squad 1 and the two joining players control squads 2 and 3."
)


class Reader:
    def __init__(self, data: bytes) -> None:
        self.data = data
        self.offset = 0

    def raw(self, size: int) -> bytes:
        end = self.offset + size
        if end > len(self.data):
            raise ValueError(f"truncated mod at byte {self.offset}")
        value = self.data[self.offset:end]
        self.offset = end
        return value

    def long(self) -> int:
        return struct.unpack("<i", self.raw(4))[0]

    def float(self) -> float:
        return struct.unpack("<f", self.raw(4))[0]

    def boolean(self) -> bool:
        value = self.raw(1)[0]
        if value not in (0, 1):
            raise ValueError(f"invalid boolean {value} at byte {self.offset - 1}")
        return bool(value)

    def string(self) -> str:
        size = self.long()
        if size < 0:
            raise ValueError(f"negative string length at byte {self.offset - 4}")
        return self.raw(size).decode("utf-8")


class Writer:
    def __init__(self) -> None:
        self.data = bytearray()

    def raw(self, value: bytes) -> None:
        self.data.extend(value)

    def long(self, value: int) -> None:
        self.raw(struct.pack("<i", value))

    def float(self, value: float) -> None:
        self.raw(struct.pack("<f", value))

    def boolean(self, value: bool) -> None:
        self.raw(bytes((1 if value else 0,)))

    def string(self, value: str) -> None:
        encoded = value.encode("utf-8")
        self.long(len(encoded))
        self.raw(encoded)


def read_mapping(reader: Reader, read_value):
    return {reader.string(): read_value() for _ in range(reader.long())}


def write_mapping(writer: Writer, values: dict, write_value) -> None:
    writer.long(len(values))
    for key, value in values.items():
        writer.string(key)
        write_value(value)


def read_record(reader: Reader) -> dict:
    record = {
        "instance_count": reader.long(),
        "typecode": reader.long(),
        "id": reader.long(),
        "name": reader.string(),
        "string_id": reader.string(),
        "mod_type": reader.long(),
        "bools": read_mapping(reader, reader.boolean),
        "floats": read_mapping(reader, reader.float),
        "longs": read_mapping(reader, reader.long),
        "vec3": {},
        "vec4": {},
        "strings": {},
        "filenames": {},
        "categories": [],
        "instances": [],
    }
    record["vec3"] = {
        reader.string(): [reader.float(), reader.float(), reader.float()]
        for _ in range(reader.long())
    }
    record["vec4"] = {
        reader.string(): [reader.float(), reader.float(), reader.float(), reader.float()]
        for _ in range(reader.long())
    }
    record["strings"] = read_mapping(reader, reader.string)
    record["filenames"] = read_mapping(reader, reader.string)
    for _ in range(reader.long()):
        category = {"name": reader.string(), "items": []}
        for _ in range(reader.long()):
            category["items"].append(
                {"name": reader.string(), "values": [reader.long(), reader.long(), reader.long()]}
            )
        record["categories"].append(category)
    for _ in range(reader.long()):
        instance = {
            "string_id": reader.string(),
            "target": reader.string(),
            "posrot": [reader.float() for _ in range(7)],
            "states": [],
        }
        instance["states"] = [reader.string() for _ in range(reader.long())]
        record["instances"].append(instance)
    return record


def write_record(writer: Writer, record: dict) -> None:
    writer.long(record["instance_count"])
    writer.long(record["typecode"])
    writer.long(record["id"])
    writer.string(record["name"])
    writer.string(record["string_id"])
    writer.long(record["mod_type"])
    write_mapping(writer, record["bools"], writer.boolean)
    write_mapping(writer, record["floats"], writer.float)
    write_mapping(writer, record["longs"], writer.long)
    writer.long(len(record["vec3"]))
    for key, value in record["vec3"].items():
        writer.string(key)
        for component in value:
            writer.float(component)
    writer.long(len(record["vec4"]))
    for key, value in record["vec4"].items():
        writer.string(key)
        for component in value:
            writer.float(component)
    write_mapping(writer, record["strings"], writer.string)
    write_mapping(writer, record["filenames"], writer.string)
    writer.long(len(record["categories"]))
    for category in record["categories"]:
        writer.string(category["name"])
        writer.long(len(category["items"]))
        for item in category["items"]:
            writer.string(item["name"])
            for value in item["values"]:
                writer.long(value)
    writer.long(len(record["instances"]))
    for instance in record["instances"]:
        writer.string(instance["string_id"])
        writer.string(instance["target"])
        for component in instance["posrot"]:
            writer.float(component)
        writer.long(len(instance["states"]))
        for state in instance["states"]:
            writer.string(state)


def parse(data: bytes) -> tuple[dict, list[dict]]:
    reader = Reader(data)
    header = {
        "filetype": reader.long(),
        "version": reader.long(),
        "author": reader.string(),
        "description": reader.string(),
        "dependencies": reader.string(),
        "references": reader.string(),
        "unknown": reader.long(),
        "record_count": reader.long(),
    }
    if header["filetype"] != 16:
        raise ValueError(f"expected editor mod filetype 16, got {header['filetype']}")
    records = [read_record(reader) for _ in range(header["record_count"])]
    if reader.offset != len(data):
        raise ValueError(f"unexpected {len(data) - reader.offset} trailing bytes")
    return header, records


def serialize(header: dict, records: list[dict]) -> bytes:
    writer = Writer()
    writer.long(header["filetype"])
    writer.long(header["version"])
    writer.string(header["author"])
    writer.string(header["description"])
    writer.string(header["dependencies"])
    writer.string(header["references"])
    writer.long(header["unknown"])
    writer.long(len(records))
    for record in records:
        write_record(writer, record)
    return bytes(writer.data)


def record_by_id(records: list[dict], string_id: str) -> dict:
    matches = [record for record in records if record["string_id"] == string_id]
    if len(matches) != 1:
        raise ValueError(f"expected one {string_id!r} record, found {len(matches)}")
    return matches[0]


def category(record: dict, name: str) -> dict:
    matches = [value for value in record["categories"] if value["name"] == name]
    if len(matches) != 1:
        raise ValueError(f"expected one {name!r} category in {record['name']!r}")
    return matches[0]


def generated_bytes(source: bytes) -> bytes:
    header, all_records = parse(source)
    records = [record for record in all_records if record["string_id"] not in GENERATED_IDS]
    character2 = record_by_id(records, f"1{MOD_SUFFIX}")
    squad2 = record_by_id(records, f"2{MOD_SUFFIX}")
    start2 = record_by_id(records, f"3{MOD_SUFFIX}")
    if character2["typecode"] != 1 or squad2["typecode"] != 52 or start2["typecode"] != 64:
        raise ValueError("x2 seed records have unexpected Kenshi type codes")

    character3 = copy.deepcopy(character2)
    character3.update(id=4, name="Wanderer 3", string_id=f"4{MOD_SUFFIX}")

    squad3 = copy.deepcopy(squad2)
    squad3.update(id=5, name="startoff- Wanderer squad 3 (co-op)", string_id=f"5{MOD_SUFFIX}")
    category(squad3, "leader")["items"] = [
        {"name": character3["string_id"], "values": [1, 0, 0]}
    ]

    start3 = copy.deepcopy(start2)
    start3.update(id=6, name="Multiplayer (Wanderer x3)", string_id=f"6{MOD_SUFFIX}")
    start3["strings"]["description"] = X3_DESCRIPTION
    category(start3, "squad")["items"].append(
        {"name": squad3["string_id"], "values": [0, 0, 0]}
    )

    header["description"] = HEADER_DESCRIPTION
    return serialize(header, records + [character3, squad3, start3])


def verify(data: bytes) -> None:
    header, records = parse(data)
    if header["record_count"] != 6 or len(records) != 6:
        raise ValueError("combined start mod must contain exactly six records")
    if len({record["string_id"] for record in records}) != 6:
        raise ValueError("record string IDs must be unique")
    start2 = record_by_id(records, f"3{MOD_SUFFIX}")
    character3 = record_by_id(records, f"4{MOD_SUFFIX}")
    squad3 = record_by_id(records, f"5{MOD_SUFFIX}")
    start3 = record_by_id(records, f"6{MOD_SUFFIX}")
    if character3["typecode"] != 1 or squad3["typecode"] != 52 or start3["typecode"] != 64:
        raise ValueError("x3 records have unexpected Kenshi type codes")
    x2_squads = [item["name"] for item in category(start2, "squad")["items"]]
    x3_squads = [item["name"] for item in category(start3, "squad")["items"]]
    leaders = [item["name"] for item in category(squad3, "leader")["items"]]
    if x2_squads != ["45550-gamedata.base", f"2{MOD_SUFFIX}"]:
        raise ValueError(f"existing x2 squad references changed: {x2_squads}")
    if x3_squads != ["45550-gamedata.base", f"2{MOD_SUFFIX}", f"5{MOD_SUFFIX}"]:
        raise ValueError(f"x3 start must reference three distinct squad templates: {x3_squads}")
    if leaders != [f"4{MOD_SUFFIX}"]:
        raise ValueError(f"third squad must reference Wanderer 3: {leaders}")
    if start3["name"] != "Multiplayer (Wanderer x3)":
        raise ValueError("x3 start has the wrong display name")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="verify without writing")
    args = parser.parse_args()

    current = CANONICAL.read_bytes()
    expected = generated_bytes(current)
    verify(expected)
    if args.check:
        if current != expected:
            raise SystemExit("canonical game-start mod is stale; run this script without --check")
        if not PACKAGED.exists() or PACKAGED.read_bytes() != expected:
            raise SystemExit("packaged game-start mod does not match the canonical artifact")
        print("PASS: x2 and x3 starts are structurally valid and package-matched")
        return

    CANONICAL.write_bytes(expected)
    PACKAGED.parent.mkdir(parents=True, exist_ok=True)
    PACKAGED.write_bytes(expected)
    print(f"wrote {CANONICAL}")
    print(f"wrote {PACKAGED}")
    print("PASS: x2 start preserved; x3 start has three distinct squad templates")


if __name__ == "__main__":
    main()
