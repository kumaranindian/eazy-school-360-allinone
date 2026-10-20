'use strict';

// The small storage surface the deletion processor needs, over a Cloud Storage
// bucket (kept separate so the processor can be tested without Storage).
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
  };
}

module.exports = { bucketStorage };
