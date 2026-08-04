package com.claude.ingestor.parser;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import org.springframework.stereotype.Component;

/**
 * Reads exactly {@code [fromOffset, toOffset)} of a file, in bounded-memory
 * chunks (see {@link ParserProperties#chunkSizeBytes}), invoking a
 * {@link LineConsumer} for each complete line found. A trailing partial
 * line (no terminating {@code \n} before {@code toOffset}) is left
 * unconsumed - {@link LineReadResult#consumedUpToOffset()} reflects that.
 *
 * Splits on the raw byte {@code 0x0A} rather than decoding the whole range
 * to a String first: {@code 0x0A} can only appear in valid UTF-8 as an
 * actual line feed (it's never a continuation byte, since those are
 * always {@code >= 0x80}), so this is safe and lets each line be decoded
 * independently without needing the whole range to be UTF-8-valid at any
 * single point in time - useful since we're reading a file that may still
 * be being written to.
 */
@Component
public class JsonlLineReader {

    private final ParserProperties properties;

    public JsonlLineReader(ParserProperties properties) {
        this.properties = properties;
    }

    public LineReadResult readRange(Path file, long fromOffset, long toOffset, LineConsumer consumer) throws IOException {
        if (toOffset <= fromOffset) {
            return new LineReadResult(fromOffset, 0, false);
        }

        long consumed = fromOffset;
        int linesEmitted = 0;
        boolean hadTrailingPartialBytes;

        try (RandomAccessFile raf = new RandomAccessFile(file.toFile(), "r")) {
            raf.seek(fromOffset);
            byte[] chunk = new byte[properties.chunkSizeBytes()];
            ByteArrayOutputStream carry = new ByteArrayOutputStream();
            long position = fromOffset;

            while (position < toOffset) {
                int toRead = (int) Math.min(chunk.length, toOffset - position);
                int n = raf.read(chunk, 0, toRead);
                if (n <= 0) {
                    break; // reached actual EOF before the requested toOffset
                }

                int segmentStart = 0;
                for (int i = 0; i < n; i++) {
                    if (chunk[i] == '\n') {
                        carry.write(chunk, segmentStart, i - segmentStart);
                        byte[] lineBytes = carry.toByteArray();
                        int len = lineBytes.length;
                        if (len > 0 && lineBytes[len - 1] == '\r') {
                            len--; // strip CR for CRLF line endings
                        }
                        String lineText = new String(lineBytes, 0, len, StandardCharsets.UTF_8);
                        long lineEnd = position + i + 1;
                        consumer.accept(lineText, consumed, lineEnd);
                        consumed = lineEnd;
                        linesEmitted++;
                        carry.reset();
                        segmentStart = i + 1;
                    }
                }
                carry.write(chunk, segmentStart, n - segmentStart);
                position += n;
            }

            hadTrailingPartialBytes = carry.size() > 0;
        }

        return new LineReadResult(consumed, linesEmitted, hadTrailingPartialBytes);
    }
}
