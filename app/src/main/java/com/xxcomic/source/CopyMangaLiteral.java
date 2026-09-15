package com.xxcomic.source;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.IOException;

/** Reads the site's data literals without executing JavaScript or replacing quoted text. */
final class CopyMangaLiteral {
    private final String input;
    private int position;

    private CopyMangaLiteral(String input) { this.input = input; }

    static Object parse(String input) throws IOException {
        CopyMangaLiteral parser = new CopyMangaLiteral(input);
        try {
            Object result = parser.value(0);
            parser.space();
            if (parser.position != input.length()) throw parser.error();
            return result;
        } catch (JSONException | NumberFormatException e) {
            throw new IOException("拷贝漫画数据格式错误", e);
        }
    }

    private Object value(int depth) throws IOException, JSONException {
        if (depth > 64) throw error();
        space();
        if (position >= input.length()) throw error();
        char c = input.charAt(position);
        if (c == '\'' || c == '"') return string();
        if (c == '[') {
            position++;
            JSONArray array = new JSONArray();
            if (take(']')) return array;
            do {
                array.put(value(depth + 1));
                if (take(']')) return array;
                if (!take(',')) throw error();
            } while (!take(']'));
            return array;
        }
        if (c == '{') {
            position++;
            JSONObject object = new JSONObject();
            if (take('}')) return object;
            do {
                space();
                String key = string();
                if (!take(':')) throw error();
                object.put(key, value(depth + 1));
                if (take('}')) return object;
                if (!take(',')) throw error();
            } while (!take('}'));
            return object;
        }
        int start = position;
        while (position < input.length() && ",]} \t\r\n".indexOf(input.charAt(position)) < 0) position++;
        String token = input.substring(start, position);
        if ("null".equals(token) || "None".equals(token)) return JSONObject.NULL;
        if ("true".equals(token) || "True".equals(token)) return true;
        if ("false".equals(token) || "False".equals(token)) return false;
        if (!token.matches("-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?")) throw error();
        if (token.indexOf('.') < 0 && token.indexOf('e') < 0 && token.indexOf('E') < 0) return Long.parseLong(token);
        double number = Double.parseDouble(token);
        if (Double.isInfinite(number) || Double.isNaN(number)) throw error();
        return number;
    }

    private String string() throws IOException {
        if (position >= input.length()) throw error();
        char quote = input.charAt(position++);
        if (quote != '\'' && quote != '"') throw error();
        StringBuilder out = new StringBuilder();
        while (position < input.length()) {
            char c = input.charAt(position++);
            if (c == quote) return out.toString();
            if (c == '\\') {
                if (position >= input.length()) throw error();
                char escaped = input.charAt(position++);
                switch (escaped) {
                    case '\\': case '/': case '\'': case '"': out.append(escaped); break;
                    case 'n': out.append('\n'); break;
                    case 'r': out.append('\r'); break;
                    case 't': out.append('\t'); break;
                    case 'b': out.append('\b'); break;
                    case 'f': out.append('\f'); break;
                    case 'u': out.append(hex(4)); break;
                    case 'x': out.append(hex(2)); break;
                    default: throw error();
                }
            } else {
                if (c < 32) throw error();
                out.append(c);
            }
        }
        throw error();
    }

    private char hex(int length) throws IOException {
        if (position + length > input.length()) throw error();
        String value = input.substring(position, position + length);
        if (!value.matches("[0-9a-fA-F]+")) throw error();
        position += length;
        return (char) Integer.parseInt(value, 16);
    }

    private boolean take(char expected) {
        space();
        if (position < input.length() && input.charAt(position) == expected) { position++; return true; }
        return false;
    }

    private void space() { while (position < input.length() && Character.isWhitespace(input.charAt(position))) position++; }
    private IOException error() { return new IOException("拷贝漫画数据格式错误，位置 " + position); }
}
