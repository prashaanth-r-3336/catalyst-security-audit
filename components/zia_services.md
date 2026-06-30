# Component Audit: Catalyst Zia Services

## Component Overview
Zia Services provides pre-built AI/ML capabilities: OCR, image analysis, face detection, sentiment analysis, object detection, and more. Functions pass data (images, text, documents) to Zia and receive structured results. Security concerns center on data privacy, input validation, and trust in Zia's output.

---

## Security Checklist

### ZIA-SEC-01 — PII/PHI Sent to Zia Without Consent/Policy Basis ★ HIGH

Zia services process the content sent to them. Sending documents or images containing PII (government IDs, medical records, financial documents) must have a lawful basis and data processing agreement.

```bash
# Zia invocations — check what data is being sent
grep -rn "catalyst\.zia\(\)\|zia()\|ZiaService\|ocr\|faceDetect\|sentiment" functions/ --include="*.js" -A 10 | \
  grep -i "passport\|license\|ssn\|medical\|health\|prescription\|financial\|statement\|document"
```

**Flag:** Any invocation that processes documents likely to contain PHI or government IDs → HIGH (requires compliance review).

---

### ZIA-SEC-02 — User-Supplied File Passed to Zia Without Validation ★ HIGH

If users upload files that are immediately passed to Zia services (e.g., OCR on uploaded document), the file must be validated first.

```bash
# Upload + Zia pipeline
grep -rn "zia\|ocr\|ZiaService" functions/ --include="*.js" -B 10 | \
  grep "upload\|req\.file\|multipart\|formdata" | grep -v "validate\|check\|mime\|magic"
```

**Checks required before Zia invocation:**
1. File MIME type validation (magic bytes)
2. File size limit
3. File content safety check (prevent adversarial inputs designed to exploit Zia processing)

---

### ZIA-SEC-03 — Zia Output Used to Drive Critical Decisions Without Human Check ★ MEDIUM

Zia outputs (sentiment scores, face match confidence, OCR text) should not drive irreversible or high-stakes operations without confidence thresholds and human-in-the-loop for edge cases.

```bash
# Zia results used in critical operations
grep -rn "zia\|ocr\|sentiment\|faceDetect" functions/ --include="*.js" -A 15 | \
  grep "delete\|approve\|reject\|block\|ban\|charge\|send\|grant" | \
  grep -v "confidence\|score\|threshold\|review"
```

---

### ZIA-SEC-04 — Zia Results Stored Without Retention Policy ★ MEDIUM

OCR results from identity documents, face detection results, and sentiment analysis of user communications are sensitive derived data.

```bash
# Zia results stored in Data Store or Cache
grep -rn "zia\|ocr\|sentiment" functions/ --include="*.js" -A 10 | \
  grep "insertRow\|updateRow\|cache.*put\|nosql.*set"
```

**Flag:** Zia-derived biometric or identity data stored without explicit TTL or retention policy → MEDIUM.

---

### ZIA-SEC-05 — Zia API Credentials Not Using Catalyst Connections ★ HIGH

```bash
# Zia API key hardcoded
grep -rn "zia\|ocr\|ZiaService" functions/ --include="*.js" -A 5 | \
  grep -i "apiKey\|api_key\|secret\|token\|Authorization" | \
  grep "=\s*['\"][A-Za-z0-9+/._-]\{20,\}['\"]"
```

---

## Scalability Checklist

### ZIA-SCALE-01 — Zia Call in Synchronous Function on Large Files

```bash
grep -rn "zia\|ocr\|ZiaService" functions/ --include="*.js" -l
# Cross-reference with function types — OCR on large PDFs in synchronous function = timeout risk
```

OCR on large documents can take 10+ seconds. Run in Immediate Job for documents over 1-2 pages.

### ZIA-SCALE-02 — No Caching of Zia Results for Identical Inputs

```bash
grep -rn "zia\|ocr\|sentiment" functions/ --include="*.js" -B 5 | \
  grep -v "cache.*get\|cache.*check"
```

If the same document or image is processed repeatedly, cache the Zia result keyed by a hash of the input (not the file name — the content hash). Use SHA-256 of file content as cache key.

### ZIA-SCALE-03 — Batch Images Processed Individually

```bash
# Zia image calls in loops
grep -rn "zia\|faceDetect\|objectDetect\|sentiment" functions/ --include="*.js" -B 5 | \
  grep "for\|while\|forEach\|\.map"
```

If Zia supports batch inference, use it. If not, dispatch individual Zia calls as parallel Immediate Jobs using a Job Pool.
