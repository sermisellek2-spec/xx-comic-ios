package com.xxcomic.local;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.UUID;

/** One durable batch. Call state-changing methods rather than assigning the public state fields. */
public final class BatchImportSession {
    public static final class Item {
        public final String uri, name, format;
        public final int selectionIndex;
        public volatile String state = "pending", error = "";
        public Item(String uri, String name, String format, int selectionIndex) {
            this.uri = text(uri); this.name = text(name); this.format = text(format); this.selectionIndex = selectionIndex;
        }
    }
    public static final class Group {
        public final String key, title;
        public final List<Item> items;
        public final boolean requiresExistingBook;
        public volatile String targetBookId;
        public Group(String key, String title, String targetBookId, List<Item> items) {
            this(key, title, targetBookId, items, false);
        }
        public Group(String key, String title, String targetBookId, List<Item> items, boolean requiresExistingBook) {
            this.key = text(key); this.title = text(title); this.targetBookId = text(targetBookId);
            this.requiresExistingBook = requiresExistingBook;
            this.items = Collections.unmodifiableList(new ArrayList<>(items));
        }
    }
    public final String taskId;
    public final List<Group> groups;
    public volatile boolean cancelled;
    private final File file;

    private BatchImportSession(File file, String taskId, List<Group> groups) {
        this.file = file; this.taskId = taskId;
        this.groups = Collections.unmodifiableList(new ArrayList<>(groups));
    }

    public static synchronized BatchImportSession create(File file, List<Group> groups) throws IOException {
        BatchImportSession existing = load(file);
        if (existing != null && !existing.cancelled) {
            for (Group group : existing.groups) for (Item item : group.items) {
                if (!finished(item)) throw new IOException("已有未结束的导入批次");
            }
        }
        BatchImportSession session = new BatchImportSession(file, UUID.randomUUID().toString(), groups);
        session.save();
        return session;
    }

    public static synchronized BatchImportSession load(File file) throws IOException {
        File backup = new File(file.getPath() + ".bak");
        // Backup means replacement did not finish; it is authoritative until removed.
        File source = backup.exists() ? backup : file;
        if (!source.exists()) return null;
        try (FileInputStream in = new FileInputStream(source)) {
            ByteArrayOutputStream bytes = new ByteArrayOutputStream();
            byte[] buffer = new byte[8192];
            int count;
            while ((count = in.read(buffer)) != -1) {
                if (bytes.size() + count > 16 * 1024 * 1024) throw new IOException("批次记录过大");
                bytes.write(buffer, 0, count);
            }
            JSONObject json = new JSONObject(new String(bytes.toByteArray(), StandardCharsets.UTF_8));
            if (json.getInt("version") != 1) throw new IOException("不支持的批次记录版本");
            String taskId = json.getString("taskId");
            UUID.fromString(taskId);
            List<Group> groups = new ArrayList<>();
            JSONArray groupJson = json.getJSONArray("groups");
            for (int g = 0; g < groupJson.length(); g++) {
                JSONObject group = groupJson.getJSONObject(g);
                List<Item> items = new ArrayList<>();
                JSONArray itemJson = group.getJSONArray("items");
                for (int i = 0; i < itemJson.length(); i++) {
                    JSONObject value = itemJson.getJSONObject(i);
                    Item item = new Item(value.getString("uri"), value.getString("name"),
                            value.getString("format"), value.getInt("selectionIndex"));
                    String state = value.getString("state");
                    if (!state.equals("pending") && !state.equals("running") && !state.equals("completed")
                            && !state.equals("skipped") && !state.equals("failed")) throw new IOException("未知的导入状态");
                    item.state = state.equals("running") ? "pending" : state;
                    item.error = value.getString("error");
                    items.add(item);
                }
                groups.add(new Group(group.getString("key"), group.getString("title"),
                        group.getString("targetBookId"), items, group.optBoolean("requiresExistingBook", false)));
            }
            BatchImportSession session = new BatchImportSession(file, taskId, groups);
            session.cancelled = json.getBoolean("cancelled");
            return session;
        } catch (JSONException | IllegalArgumentException e) {
            throw new IOException("批次记录损坏，已保留原文件", e);
        }
    }

    public synchronized void setTargetBookId(Group group, String bookId) throws IOException {
        change(group, null, "", "", bookId);
    }
    public synchronized void start(Group group, Item item) throws IOException {
        if (cancelled) throw new IOException("导入批次已取消");
        if (item.state.equals("pending")) change(group, item, "running", "", group.targetBookId);
    }
    public synchronized void complete(Group group, Item item, String bookId) throws IOException {
        change(group, item, "completed", "", text(bookId).isEmpty() ? group.targetBookId : bookId);
    }
    public synchronized void fail(Group group, Item item, String error) throws IOException {
        change(group, item, "failed", error, group.targetBookId);
    }
    public synchronized void skip(Group group, Item item) throws IOException {
        change(group, item, "skipped", "", group.targetBookId);
    }
    /** Resume only after the previous worker has stopped; also resets its interrupted running item. */
    public synchronized void retryFailed() throws IOException { changeUnfinished(false); }
    public synchronized void cancel() throws IOException { changeUnfinished(true); }
    public synchronized boolean hasPending() { return !pendingGroups().isEmpty(); }
    public synchronized List<Group> pendingGroups() {
        List<Group> pending = new ArrayList<>();
        if (!cancelled) for (Group group : groups) for (Item item : group.items) {
            if (item.state.equals("pending") || item.state.equals("running")) {
                pending.add(group);
                break;
            }
        }
        return pending;
    }

    private void change(Group group, Item item, String state, String error, String bookId) throws IOException {
        if (!groups.contains(group) || (item != null && !group.items.contains(item))) {
            throw new IllegalArgumentException("导入项不属于当前批次");
        }
        if (cancelled || (item != null && finished(item))) return;
        String oldTarget = group.targetBookId, oldState = item == null ? "" : item.state;
        String oldError = item == null ? "" : item.error;
        group.targetBookId = text(bookId);
        if (item != null) { item.state = state; item.error = text(error); }
        try { save(); } catch (IOException e) {
            group.targetBookId = oldTarget;
            if (item != null) { item.state = oldState; item.error = oldError; }
            throw e;
        }
    }

    private void changeUnfinished(boolean cancel) throws IOException {
        if (cancelled) return;
        List<Item> changed = new ArrayList<>();
        List<String> states = new ArrayList<>(), errors = new ArrayList<>();
        for (Group group : groups) for (Item item : group.items) {
            if ((cancel && !finished(item)) || (!cancel && (item.state.equals("failed") || item.state.equals("running")))) {
                changed.add(item); states.add(item.state); errors.add(item.error);
                item.state = cancel ? "skipped" : "pending";
                item.error = "";
            }
        }
        cancelled = cancel;
        try { save(); } catch (IOException e) {
            cancelled = false;
            for (int i = 0; i < changed.size(); i++) {
                changed.get(i).state = states.get(i); changed.get(i).error = errors.get(i);
            }
            throw e;
        }
    }

    private void save() throws IOException {
        byte[] data;
        try {
            JSONArray groupJson = new JSONArray();
            for (Group group : groups) {
                JSONArray items = new JSONArray();
                for (Item item : group.items) items.put(new JSONObject().put("uri", item.uri).put("name", item.name)
                        .put("format", item.format).put("selectionIndex", item.selectionIndex)
                        .put("state", item.state).put("error", item.error));
                groupJson.put(new JSONObject().put("key", group.key).put("title", group.title)
                        .put("targetBookId", group.targetBookId).put("requiresExistingBook", group.requiresExistingBook).put("items", items));
            }
            data = new JSONObject().put("version", 1).put("taskId", taskId).put("cancelled", cancelled)
                    .put("groups", groupJson).toString().getBytes(StandardCharsets.UTF_8);
        } catch (JSONException e) { throw new IOException("无法保存批次记录", e); }
        File parent = file.getAbsoluteFile().getParentFile();
        if (!parent.isDirectory() && !parent.mkdirs()) throw new IOException("无法创建批次记录目录");
        File temp = new File(file.getPath() + ".tmp"), backup = new File(file.getPath() + ".bak");
        try (FileOutputStream out = new FileOutputStream(temp)) {
            out.write(data);
            out.getFD().sync();
        }
        if (backup.exists()) {
            if (file.exists() && (!file.isFile() || !file.delete())) throw new IOException("无法替换批次记录");
        } else if (file.exists() && (!file.isFile() || !file.renameTo(backup))) {
            throw new IOException("无法备份批次记录");
        }
        if (!temp.renameTo(file)) {
            if (!file.exists() && backup.exists()) backup.renameTo(file);
            throw new IOException("无法安装批次记录，旧记录已保留");
        }
        if (backup.exists() && !backup.delete()) throw new IOException("无法完成批次记录替换，旧记录已保留");
    }

    private static boolean finished(Item item) {
        return item.state.equals("completed") || item.state.equals("skipped");
    }
    private static String text(String value) { return value == null ? "" : value; }
}
