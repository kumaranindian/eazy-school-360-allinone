'use strict';

// The small storage surface the deletion processor and the admission document
// workflow need, over a Cloud Storage bucket (kept separate so they can be
// tested without Storage).
function bucketStorage(bucket) {
  const names = async (prefix) => {
    const [files] = await bucket.getFiles({ prefix });
    return files.map((f) => f.name);
  };
  return {
    // Removes every object under [prefix]; returns how many.
    deletePrefix: async (prefix) => {
      const [files] = await bucket.getFiles({ prefix });
      await Promise.all(files.map((f) => f.delete({ ignoreNotFound: true })));
      return files.length;
    },
    list: names,
    deleteFile: async (path) => void (await bucket.file(path).delete({ ignoreNotFound: true })),
    // The first [n] bytes of an object (to check its real format).
    head: async (path, n) => {
      const [buf] = await bucket.file(path).download({ start: 0, end: n - 1 });
      return buf;
    },
    // { exists, size, contentType } of one object, read with admin rights (what
    // is actually stored, not what a client claims).
    stat: async (path) => {
      const file = bucket.file(path);
      const [exists] = await file.exists();
      if (!exists) return { exists: false };
      const [meta] = await file.getMetadata();
      return { exists: true, size: Number(meta.size), contentType: meta.contentType || null };
    },
  };
}

module.exports = { bucketStorage };
