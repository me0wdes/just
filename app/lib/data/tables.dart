// Version 1 stores protocol snapshots as JSON; projected tables remain separate
// from canonical snapshots and the durable operation queue.
const schemaStatements = [
  'CREATE TABLE canonicalEntities(type TEXT NOT NULL,id TEXT NOT NULL,value TEXT NOT NULL,revision INTEGER NOT NULL,PRIMARY KEY(type,id))',
  'CREATE TABLE pendingOperations(id TEXT PRIMARY KEY,sequence INTEGER NOT NULL UNIQUE,value TEXT NOT NULL,status TEXT NOT NULL DEFAULT \'pending\',error TEXT,effect TEXT)',
  'CREATE TABLE projectedTasks(id TEXT PRIMARY KEY,value TEXT NOT NULL)',
  'CREATE TABLE projectedLists(id TEXT PRIMARY KEY,value TEXT NOT NULL)',
  'CREATE TABLE recurrenceRules(id TEXT PRIMARY KEY,value TEXT NOT NULL)',
  'CREATE TABLE completionLinks(operationId TEXT PRIMARY KEY,parentId TEXT NOT NULL,provisionalId TEXT,canonicalId TEXT)',
  'CREATE TABLE localSettings(key TEXT PRIMARY KEY,value TEXT NOT NULL)',
  'CREATE TABLE syncMetadata(key TEXT PRIMARY KEY,value TEXT NOT NULL)',
  'CREATE TABLE notificationIds(taskId TEXT PRIMARY KEY,notificationId INTEGER NOT NULL UNIQUE)',
];
