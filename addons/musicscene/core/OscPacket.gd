extends RefCounted
## Minimal, dependency-free OSC 1.0 codec (messages + bundles).
##
## All multi-byte numbers are big-endian; all OSC-strings and blobs are null-terminated and
## padded to a multiple of 4 bytes. This layer is intentionally swappable: a third-party OSC
## library could replace it without touching the rest of MusicScene, as long as it produces
## the same {address: String, args: Array} dictionaries on decode and accepts them on encode.
##
## GDScript -> OSC type mapping on encode:
##   bool                -> T / F      (no payload)
##   int  (fits int32)   -> i          (32-bit)
##   int  (larger)       -> h          (64-bit)
##   float               -> f          (32-bit; standard, most compatible with Max/Pd/SC)
##   String/StringName   -> s
##   PackedByteArray     -> b          (blob)
##   anything else       -> s          (str(value))

# ---------------------------------------------------------------------------
# Encoding
# ---------------------------------------------------------------------------

## Encode a single OSC message to bytes.
static func encode_message(address: String, args: Array = []) -> PackedByteArray:
	var sp := StreamPeerBuffer.new()
	sp.big_endian = true
	_put_string(sp, address)

	var typetag := ","
	var payload := StreamPeerBuffer.new()
	payload.big_endian = true

	for a in args:
		match typeof(a):
			TYPE_BOOL:
				typetag += "T" if a else "F"
			TYPE_INT:
				if a > 2147483647 or a < -2147483648:
					typetag += "h"
					payload.put_64(a)
				else:
					typetag += "i"
					payload.put_32(a)
			TYPE_FLOAT:
				typetag += "f"
				payload.put_float(a)
			TYPE_STRING, TYPE_STRING_NAME:
				typetag += "s"
				_put_string(payload, str(a))
			TYPE_PACKED_BYTE_ARRAY:
				typetag += "b"
				_put_blob(payload, a)
			_:
				typetag += "s"
				_put_string(payload, str(a))

	_put_string(sp, typetag)
	sp.put_data(payload.data_array)
	return sp.data_array


## Encode an OSC bundle. `elements` may contain raw PackedByteArrays (already-encoded
## messages/bundles) or {address, args} dictionaries. `timetag` of 1 means "immediately".
static func encode_bundle(elements: Array, timetag: int = 1) -> PackedByteArray:
	var sp := StreamPeerBuffer.new()
	sp.big_endian = true
	_put_string(sp, "#bundle")
	sp.put_64(timetag)
	for el in elements:
		var b: PackedByteArray
		if el is PackedByteArray:
			b = el
		elif el is Dictionary:
			b = encode_message(String(el.get("address", "")), el.get("args", []))
		else:
			continue
		sp.put_32(b.size())
		sp.put_data(b)
	return sp.data_array


# ---------------------------------------------------------------------------
# Decoding
# ---------------------------------------------------------------------------

## Decode a UDP datagram into an Array of {address: String, args: Array} dictionaries.
## A single message yields one entry; a bundle is flattened (recursively) into many.
static func decode(bytes: PackedByteArray) -> Array:
	if bytes.size() == 0:
		return []
	if bytes[0] == 0x23:  # '#' => "#bundle"
		return _decode_bundle(bytes)
	var m := _decode_message(bytes)
	return [m] if m != null else []


static func _decode_message(bytes: PackedByteArray) -> Variant:
	var sp := StreamPeerBuffer.new()
	sp.big_endian = true
	sp.data_array = bytes
	var address := _read_string(sp)
	if not address.begins_with("/"):
		return null
	var args: Array = []
	if sp.get_position() < bytes.size():
		var typetag := _read_string(sp)
		if typetag.begins_with(","):
			for i in range(1, typetag.length()):
				match typetag[i]:
					"i", "c", "r":
						args.append(sp.get_32())
					"f":
						args.append(sp.get_float())
					"h", "t":
						args.append(sp.get_64())
					"d":
						args.append(sp.get_double())
					"s", "S":
						args.append(_read_string(sp))
					"b", "m":
						args.append(_read_blob(sp))
					"T":
						args.append(true)
					"F":
						args.append(false)
					"N":
						args.append(null)
					"I":
						args.append(INF)
					_:
						# Unknown tag with no known width: stop to avoid misaligned reads.
						break
	return {"address": address, "args": args}


static func _decode_bundle(bytes: PackedByteArray) -> Array:
	var sp := StreamPeerBuffer.new()
	sp.big_endian = true
	sp.data_array = bytes
	_read_string(sp)  # "#bundle"
	if sp.get_position() + 8 > bytes.size():
		return []
	sp.get_64()  # timetag (ignored; we treat everything as immediate)
	var out: Array = []
	while sp.get_position() + 4 <= bytes.size():
		var size := sp.get_32()
		if size <= 0:
			break
		var start := sp.get_position()
		if start + size > bytes.size():
			break
		out.append_array(decode(bytes.slice(start, start + size)))
		sp.seek(start + size)
	return out


# ---------------------------------------------------------------------------
# Low-level helpers
# ---------------------------------------------------------------------------

static func _put_string(sp: StreamPeerBuffer, s: String) -> void:
	var b := s.to_utf8_buffer()
	sp.put_data(b)
	sp.put_u8(0)
	var total := b.size() + 1
	var pad := (4 - (total % 4)) % 4
	for _i in pad:
		sp.put_u8(0)


static func _put_blob(sp: StreamPeerBuffer, blob: PackedByteArray) -> void:
	sp.put_32(blob.size())
	sp.put_data(blob)
	var pad := (4 - (blob.size() % 4)) % 4
	for _i in pad:
		sp.put_u8(0)


static func _read_string(sp: StreamPeerBuffer) -> String:
	var bytes := sp.data_array
	var start := sp.get_position()
	var i := start
	while i < bytes.size() and bytes[i] != 0:
		i += 1
	var s := bytes.slice(start, i).get_string_from_utf8()
	var total := (i - start) + 1
	var pad := (4 - (total % 4)) % 4
	sp.seek(min(start + total + pad, bytes.size()))
	return s


static func _read_blob(sp: StreamPeerBuffer) -> PackedByteArray:
	var n := sp.get_32()
	if n <= 0:
		return PackedByteArray()
	var res := sp.get_data(n)
	var blob: PackedByteArray = res[1] if res is Array and res.size() > 1 else PackedByteArray()
	var pad := (4 - (n % 4)) % 4
	if pad > 0:
		sp.get_data(pad)
	return blob
