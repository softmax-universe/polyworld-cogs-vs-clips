// Shared Polyworld file header; game decoders still validate the complete replay.
export async function replayMode(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Replay download failed: HTTP ${response.status}`);
  let bytes = new Uint8Array(await response.arrayBuffer());
  const gzip = bytes[0] === 31 && bytes[1] === 139;
  const zlib = (bytes[0] & 15) === 8 && bytes[0] >> 4 <= 7 && ((bytes[0] << 8) | bytes[1]) % 31 === 0;
  if (gzip || zlib) {
    const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream(gzip ? 'gzip' : 'deflate'));
    bytes = new Uint8Array(await new Response(stream).arrayBuffer());
  }
  const decode = new TextDecoder();
  const magic = 'POLYWORLDREPLAY';
  const fixed = magic.length;
  const start = fixed + 6;
  if (decode.decode(bytes.subarray(0, fixed)) !== magic) return null;
  if (bytes.length < start) throw new Error('Truncated Polyworld replay header');
  const header = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const size = header.getUint16(fixed + 4, true);
  if (header.getUint16(fixed, true) !== 2 || size < 1 || size > 64 || start + size > bytes.length) {
    throw new Error('Unsupported Polyworld replay header');
  }
  const game = decode.decode(bytes.subarray(start, start + size));
  const version = header.getUint16(fixed + 2, true);
  if (game === 'four_score' && version === 3) return 'fourscore';
  if (game === 'cogs_vs_clips' && version === 4) return 'cooperative';
  throw new Error(`Unsupported Polyworld replay: ${game} version ${version}`);
}
