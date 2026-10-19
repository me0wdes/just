// SQLite's native backup includes committed WAL pages while the source stays open.
export async function createBackup(store,path){await store.backupTo(path);return path;}
