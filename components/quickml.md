# Component Audit: Catalyst QuickML

## Component Overview
QuickML enables deploying and invoking machine learning models within Catalyst. Functions call QuickML endpoints to run predictions. Security concerns include adversarial inputs, data privacy (training data and inference inputs), and model output trust.

---

## Security Checklist

### QML-SEC-01 — Raw User Input to Model Without Validation ★ HIGH

ML models are not robust to adversarial inputs. Unvalidated user input passed directly to a model can cause unexpected behavior, model manipulation, or prompt injection (for language models).

```bash
# ML invocation with user input
grep -rn "catalyst\.ml\(\)\|quickml\|QuickML\|\.predict\|\.inference" functions/ --include="*.js" -B 5 -A 5 | \
  grep "req\.\|body\.\|param\.\|query\."
```

**Required input checks before model inference:**
- Type validation (string, number, image — match what model expects)
- Length/size limits (prevent oversized inputs)
- Content policy check for text inputs (if model is a language model)
- Numeric range validation for tabular data

---

### QML-SEC-02 — PII in Model Inference Inputs ★ HIGH

Data sent to QuickML for inference may be logged, cached, or used for model improvement. Sending raw PII (emails, names, health data) to a model creates compliance risk.

```bash
grep -rn "\.predict\|\.inference\|quickml\|ml()" functions/ --include="*.js" -B 10 | \
  grep -i "email\|name\|phone\|address\|ssn\|health\|medical\|dob"
```

**Fix:** Anonymize or tokenize PII before sending to QuickML. Send feature vectors, not raw personal data.

---

### QML-SEC-03 — Model Output Trusted Without Validation ★ MEDIUM

Model outputs should never be used directly in high-stakes operations without a confidence threshold check and output validation.

```bash
# ML output used directly without validation
grep -rn "predict\|inference" functions/ --include="*.js" -A 10 | \
  grep "approve\|reject\|delete\|create\|send\|charge" | \
  grep -v "confidence\|score\|threshold\|probability"
```

**Pattern for safe model output usage:**
```js
const prediction = await catalyst.ml().model(MODEL_ID).predict(input);

// Check confidence threshold before acting
if (prediction.confidence < CONFIDENCE_THRESHOLD) {
  // Route to human review
  return enqueueForManualReview(input, prediction);
}

// Validate output is in expected range/enum
if (!VALID_CATEGORIES.includes(prediction.label)) {
  throw new Error('Unexpected model output');
}
```

---

### QML-SEC-04 — Hardcoded Model ID or API Key ★ MEDIUM

```bash
# Hardcoded model IDs or QuickML credentials
grep -rn "model(\|MODEL_ID\|quickml.*key\|ml.*token" functions/ --include="*.js" | \
  grep -E "['\"][0-9a-zA-Z]{8,}['\"]"
```

**Fix:** Model IDs should be in Catalyst Environment Variables. Any QuickML API credentials must be in Catalyst Connections.

---

## Scalability Checklist

### QML-SCALE-01 — Synchronous Inference on Large Inputs

```bash
# ML inference in synchronous functions
grep -rn "predict\|inference" functions/ --include="*.js" -l
# Cross-reference with function types (advanced/basic IO = synchronous)
```

ML inference can be slow (hundreds of milliseconds to seconds). For batch inference or large inputs, use Immediate Jobs rather than blocking a synchronous function.

### QML-SCALE-02 — No Caching of Repeated Identical Inference

```bash
# Inference calls without cache check
grep -rn "predict\|inference" functions/ --include="*.js" -B 10 | \
  grep -v "cache.*get\|cache.*check"
```

If the same input produces the same output (deterministic models), caching inference results for repeated inputs reduces cost and latency.

### QML-SCALE-03 — Model Invoked Per Loop Iteration

```bash
grep -rn "predict\|inference" functions/ --include="*.js" -B 5 | \
  grep "for\|while\|forEach\|\.map"
```

**Fix:** Use batch inference API if the model supports it; send multiple inputs in a single API call rather than N individual calls.
