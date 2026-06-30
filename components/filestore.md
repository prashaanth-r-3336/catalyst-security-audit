# Component Audit: Catalyst File Store

## Component Overview
Catalyst File Store provides file upload, download, and management. Files are referenced by numeric row IDs. Without ownership checks, any user can access any other user's files by guessing or enumerating IDs.

---

## Security Checklist

### FS-SEC-01 — File IDOR via Row ID ★ HIGH

File Store rows are auto-incremented integers. Any function that serves file content based on a user-supplied `rowId` without an ownership check is vulnerable.

```bash
# File downloads using request-supplied row ID
grep -rn "filestore\(\)\.folder\|downloadFile\|getFileDetailsById\|getFile" functions/ --include="*.js" -B 5 -A 5 | \
  grep "req\.\|body\.\|param\.\|query\."

# Row ID from request used directly
grep -rn "filestore" functions/ --include="*.js" -A 10 | grep "req\.params\|req\.query\|req\.body" | head -20
```

**Vulnerable pattern:**
```js
// VULNERABLE — no ownership check
const file = await catalyst.filestore().folder('UserDocuments').getFileDetailsById(req.params.fileId);
return res.send(await file.getDownloadUrl());
```

**Safe pattern:**
```js
// SAFE — verify ownership before serving
const file = await catalyst.filestore().folder('UserDocuments').getFileDetailsById(req.params.fileId);
if (file.uploaded_by !== currentUser.userId) {
  return res.status(403).json({ error: 'Forbidden' });
}
return res.send(await file.getDownloadUrl());
```

---

### FS-SEC-02 — File Upload Validation ★ HIGH

Check that uploaded files are validated for type and size. Malicious files (scripts, executables) uploaded and later executed or served are an RCE vector.

```bash
# Upload endpoints
grep -rn "upload\|Upload\|multipart\|formdata" functions/ --include="*.js" -A 10 | \
  grep -i "filestore\|folder"
```

**Required checks:**
1. File extension allowlist (not denylist)
2. MIME type validation from magic bytes (not just extension or Content-Type header)
3. File size limit enforcement before writing to File Store
4. Filename sanitization — strip path separators, null bytes, `..\`

```bash
# Check for file type validation
grep -rn "upload\|Upload" functions/ --include="*.js" -A 10 | \
  grep -i "mime\|magic\|extension\|allowlist\|whitelist\|type"
# Check for size limit
grep -rn "upload\|Upload" functions/ --include="*.js" -A 10 | \
  grep -i "size\|limit\|maxSize"
```

**Finding:** If upload handler lacks MIME/magic-byte validation → HIGH.

---

### FS-SEC-03 — Path Traversal in File Operations

```bash
# User input used in file path operations
grep -rn "path\.join\|path\.resolve\|__dirname\|folder(" functions/ --include="*.js" | \
  grep "req\.\|body\.\|param\.\|query\."

# Dangerous patterns
grep -rn "\.\.\/" functions/ --include="*.js"
grep -rn "decodeURIComponent.*path\|decodeURI.*file" functions/ --include="*.js"
```

**Fix:** Always `path.normalize()` and verify the resolved path starts with the expected base directory.

---

### FS-SEC-04 — Serving Files with Wrong Content-Type

```bash
# Download handlers — check Content-Disposition
grep -rn "download\|Download\|getDownloadUrl" functions/ --include="*.js" -A 5 | \
  grep -v "Content-Disposition\|attachment\|nosniff"
```

Files served without `Content-Disposition: attachment` and `X-Content-Type-Options: nosniff` may be executed by the browser (HTML files with scripts, SVGs, etc.).

---

### FS-SEC-05 — Unauthenticated File Access Endpoint

For every function that serves files:
- Is the function type Advanced I/O or Basic I/O?
- If Advanced I/O, does it have an explicit auth check before serving?

```bash
# Advanced I/O functions that call filestore
grep -rn "filestore\|folder(" functions/ --include="*.js" -l
# For each file, check which catalyst-config.json type it has
```

---

## Scalability Checklist

### FS-SCALE-01 — Loading Entire File into Memory

```bash
# Reading entire file buffer in function
grep -rn "readFile\|Buffer\.from\|\.buffer\|toBuffer" functions/ --include="*.js"
```

For large files, streaming is required. Loading a 100MB file into a 512MB function memory causes OOM.

**Fix:** Use streaming APIs — pipe the file stream to the response rather than loading into a Buffer.

### FS-SCALE-02 — Listing All Files Without Pagination

```bash
grep -rn "listFiles\|getAllFiles\|getFiles()" functions/ --include="*.js" | grep -v "limit\|pageToken\|cursor"
```

**Fix:** Always paginate file listings. Large folders with thousands of files will OOM on full list.

### FS-SCALE-03 — Upload Without Size Pre-check

Large uploads should be rejected early (before writing to File Store) to avoid wasting function execution time and storage.

```bash
# Upload handlers with no size check before writing
grep -rn "upload\|filestore.*put\|filestore.*write" functions/ --include="*.js" -B 10 | \
  grep -v "size\|limit\|length"
```

---

## Common Anti-Patterns

| Anti-Pattern | Risk | Fix |
|---|---|---|
| Returning raw Catalyst file URL to unauthenticated users | Enables URL sharing bypassing auth | Generate short-lived signed URLs; serve through auth-protected endpoint |
| Using original filename from upload for storage | Path traversal, filename injection | Generate UUID-based filenames for storage |
| No virus/malware scan on upload | Malware distribution via platform | Integrate file scanning before making available |
| Storing executables (.exe, .sh, .bat, .jar) in public folder | RCE if served directly | Reject executable file types at upload |
