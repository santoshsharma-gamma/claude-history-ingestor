package com.claude.ingestor.util;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Minimal, dependency-free JSON parser.
 *
 * Deliberately doesn't use Jackson even though it's on the classpath
 * (via {@code spring-boot-starter-webmvc}): Spring Boot 4 ships Jackson 3,
 * which renamed its packages/groupId ({@code com.fasterxml.jackson.*} ->
 * {@code tools.jackson.*}) and changed several APIs (checked exceptions
 * became unchecked, {@code ObjectMapper} construction moved to a builder
 * on {@code JsonMapper}, etc). Rather than guess at exact 3.x API shapes
 * for something this self-contained, this parser has zero dependencies
 * and zero risk of drifting out of sync with a Jackson version.
 *
 * Parses into plain Java objects:
 *   object -> LinkedHashMap<String,Object>
 *   array  -> ArrayList<Object>
 *   string -> String
 *   number -> Long (no fraction/exponent) or Double
 *   true/false -> Boolean
 *   null -> null
 */
public final class Json {

    private Json() {
    }

    public static Object parse(String text) {
        Parser p = new Parser(text);
        p.skipWhitespace();
        Object value = p.parseValue();
        p.skipWhitespace();
        return value;
    }

    /** Appends the JSON-escaped form of s (without surrounding quotes) to sb. */
    public static void escapeInto(StringBuilder sb, String s) {
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"':
                    sb.append("\\\"");
                    break;
                case '\\':
                    sb.append("\\\\");
                    break;
                case '\n':
                    sb.append("\\n");
                    break;
                case '\r':
                    sb.append("\\r");
                    break;
                case '\t':
                    sb.append("\\t");
                    break;
                case '\b':
                    sb.append("\\b");
                    break;
                case '\f':
                    sb.append("\\f");
                    break;
                default:
                    if (c < 0x20) {
                        sb.append(String.format("\\u%04x", (int) c));
                    } else {
                        sb.append(c);
                    }
            }
        }
    }

    /** Returns {@code s} as a quoted, escaped JSON string literal (e.g. {@code "he said \"hi\""}). Null-safe: returns {@code ""} for null. */
    public static String quote(String s) {
        if (s == null) {
            return "\"\"";
        }
        StringBuilder sb = new StringBuilder(s.length() + 2);
        sb.append('"');
        escapeInto(sb, s);
        sb.append('"');
        return sb.toString();
    }

    private static final class Parser {
        private final String s;
        private int i;
        private final int n;

        Parser(String s) {
            this.s = s;
            this.i = 0;
            this.n = s.length();
        }

        void skipWhitespace() {
            while (i < n) {
                char c = s.charAt(i);
                if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
                    i++;
                } else {
                    break;
                }
            }
        }

        Object parseValue() {
            if (i >= n) {
                throw new JsonParseException("Unexpected end of input");
            }
            char c = s.charAt(i);
            switch (c) {
                case '{':
                    return parseObject();
                case '[':
                    return parseArray();
                case '"':
                    return parseString();
                case 't':
                    expectLiteral("true");
                    return Boolean.TRUE;
                case 'f':
                    expectLiteral("false");
                    return Boolean.FALSE;
                case 'n':
                    expectLiteral("null");
                    return null;
                default:
                    return parseNumber();
            }
        }

        Map<String, Object> parseObject() {
            Map<String, Object> map = new LinkedHashMap<>();
            i++; // consume '{'
            skipWhitespace();
            if (i < n && s.charAt(i) == '}') {
                i++;
                return map;
            }
            while (true) {
                skipWhitespace();
                if (i >= n || s.charAt(i) != '"') {
                    throw new JsonParseException("Expected string key at position " + i);
                }
                String key = parseString();
                skipWhitespace();
                if (i >= n || s.charAt(i) != ':') {
                    throw new JsonParseException("Expected ':' at position " + i);
                }
                i++; // consume ':'
                skipWhitespace();
                Object value = parseValue();
                map.put(key, value);
                skipWhitespace();
                if (i >= n) {
                    throw new JsonParseException("Unexpected end of object");
                }
                char ch = s.charAt(i);
                if (ch == ',') {
                    i++;
                    continue;
                } else if (ch == '}') {
                    i++;
                    break;
                } else {
                    throw new JsonParseException("Expected ',' or '}' at position " + i);
                }
            }
            return map;
        }

        List<Object> parseArray() {
            List<Object> list = new ArrayList<>();
            i++; // consume '['
            skipWhitespace();
            if (i < n && s.charAt(i) == ']') {
                i++;
                return list;
            }
            while (true) {
                skipWhitespace();
                Object value = parseValue();
                list.add(value);
                skipWhitespace();
                if (i >= n) {
                    throw new JsonParseException("Unexpected end of array");
                }
                char ch = s.charAt(i);
                if (ch == ',') {
                    i++;
                    continue;
                } else if (ch == ']') {
                    i++;
                    break;
                } else {
                    throw new JsonParseException("Expected ',' or ']' at position " + i);
                }
            }
            return list;
        }

        String parseString() {
            StringBuilder sb = new StringBuilder();
            i++; // consume opening quote
            while (true) {
                if (i >= n) {
                    throw new JsonParseException("Unterminated string");
                }
                char c = s.charAt(i);
                if (c == '"') {
                    i++;
                    break;
                } else if (c == '\\') {
                    i++;
                    if (i >= n) {
                        throw new JsonParseException("Unterminated escape sequence");
                    }
                    char esc = s.charAt(i);
                    switch (esc) {
                        case '"':
                            sb.append('"');
                            break;
                        case '\\':
                            sb.append('\\');
                            break;
                        case '/':
                            sb.append('/');
                            break;
                        case 'n':
                            sb.append('\n');
                            break;
                        case 't':
                            sb.append('\t');
                            break;
                        case 'r':
                            sb.append('\r');
                            break;
                        case 'b':
                            sb.append('\b');
                            break;
                        case 'f':
                            sb.append('\f');
                            break;
                        case 'u':
                            if (i + 4 >= n) {
                                throw new JsonParseException("Invalid unicode escape");
                            }
                            String hex = s.substring(i + 1, i + 5);
                            sb.append((char) Integer.parseInt(hex, 16));
                            i += 4;
                            break;
                        default:
                            throw new JsonParseException("Invalid escape character: " + esc);
                    }
                    i++;
                } else {
                    sb.append(c);
                    i++;
                }
            }
            return sb.toString();
        }

        Object parseNumber() {
            int start = i;
            if (i < n && (s.charAt(i) == '-' || s.charAt(i) == '+')) {
                i++;
            }
            boolean isDouble = false;
            while (i < n) {
                char c = s.charAt(i);
                if (Character.isDigit(c)) {
                    i++;
                } else if (c == '.' || c == 'e' || c == 'E' || c == '+' || c == '-') {
                    isDouble = true;
                    i++;
                } else {
                    break;
                }
            }
            String numStr = s.substring(start, i);
            if (numStr.isEmpty()) {
                throw new JsonParseException("Invalid number at position " + start);
            }
            try {
                if (isDouble) {
                    return Double.parseDouble(numStr);
                }
                return Long.parseLong(numStr);
            } catch (NumberFormatException e) {
                return Double.parseDouble(numStr);
            }
        }

        void expectLiteral(String literal) {
            if (i + literal.length() > n || !s.regionMatches(i, literal, 0, literal.length())) {
                throw new JsonParseException("Expected literal '" + literal + "' at position " + i);
            }
            i += literal.length();
        }
    }

    public static final class JsonParseException extends RuntimeException {
        public JsonParseException(String message) {
            super(message);
        }
    }
}