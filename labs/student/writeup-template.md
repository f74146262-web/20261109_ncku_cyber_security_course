# Writeup Template

> You may reorganize, rename, or replace the sections in this template to fit your own writeup. You do not have to follow the exact structure. What matters is that your writeup covers the required grading areas.
>
> Do not claim steps you did not actually perform. Failed attempts and troubleshooting are valid evidence when reported honestly.
>
> Please write in English or Mandarin.
>
> Grading: environment 20%, source and conditions 20%, reproduction and evidence 30%, patching 20%, fourth effect 10%. Each bonus item is +10%, with a total cap of 100%.
>
> Format: PDF
>
> Nice tool for converting Markdown to PDF (good for handling page breaks): https://md2pdf.moon-jam.me/ 

| Item | Content |
|---|---|
| Name | {{name}} |
| Student ID | {{student_id}} |

## 1. CVE and PoC Source

| Item | Content |
|---|---|
| CVE | {{cve_id}} |
| Official advisory | {{advisory_url}} |
| Affected versions | {{affected_versions}} |
| Patched version | {{patched_version}} |
| PoC source | {{poc_repository}} |

## 2. Environment and Requirements

I tested the PoC using the following environment:

| Item | Configuration | Verified |
|---|---|---|
| Architecture | `linux/amd64` | {{result}} |
| PHP | `8.3.35` | {{result}} |
| `memory_limit` | `8M` at request startup | {{result}} |
| `max_input_vars` | `1000` at request startup | {{result}} |
| `display_errors` | `On` at request startup | {{result}} |
| Moodle page overrides | `256M / 5000 / Off` | {{result}} |
| Apache | Single prefork worker | {{result}} |

These settings matter because {{explanation_of_requirements}}.

This environment differs from a default Moodle deployment. My results demonstrate {{supported_conclusion}}, but do not establish {{limitations}}.

## 3. Reproduction

I followed these steps to reproduce the vulnerability:

1. {{environment_setup}}
2. {{poc_execution}}
3. {{command_execution_and_flag}}
4. {{moodle_test_effect}}

Relevant commands:

```sh
{{commands_used}}
```

Observed output:

```text
{{execution_output}}
```

## 4. Experimental Evidence

### 4.1 Remote Code Execution

I tested remote command execution by running `id` through the PoC.

```text
{{id_output}}
```

The observed execution identity was {{execution_identity}}, which indicates {{conclusion}}.

### 4.2 Flag Retrieval

I attempted to retrieve the flag through the vulnerable service using {{method}}.

```text
{{flag_commands_and_output}}
```

This result was obtained by {{evidence_method}}, rather than directly reading the flag using Docker.

### 4.3 Moodle Impact

I tested {{effect_name}} on fictional Moodle data.

**Before:** {{original_state}}

**After:** {{modified_state}}

**Reset:** {{restored_state}}

```text
{{commands_and_evidence}}
```

I verified the effect using {{verification_method}} and checked the reset using {{reset_verification}}.

For the other in-class effects, {{brief_description_if_applicable}}.

## 5. Patch Verification

I compared PHP 8.3.35 with PHP 8.3.36.

| Observation | PHP 8.3.35 | PHP 8.3.36 |
|---|---|---|
| PHP version | {{version_before}} | {{version_after}} |
| PoC result | {{poc_before}} | {{poc_after}} |
| New execution proof | {{proof_before}} | {{proof_after}} |
| Moodle availability | {{moodle_before}} | {{moodle_after}} |

Commands used:

```sh
{{patch_and_verification_commands}}
```

Patched retest output:

```text
{{patched_test_output}}
```

I observed {{patch_observation}}. These results support {{patch_conclusion}}, subject to {{patch_limitations}}.

## 6. Fourth Effect (10%)

I implemented an additional effect on fictional Moodle test data.

| Item | Description |
|---|---|
| Effect | {{effect_name}} |
| Target data | {{target_data}} |
| Modified field | {{modified_field}} |
| Script or command | {{command_or_script}} |

**Before:** {{original_state}}

**After:** {{modified_state}}

**Reset:** {{restored_state}}

```text
{{fourth_effect_evidence}}
```

I verified the modification and reset using {{verification_method}}.

## 7. Analysis

My reproduction {{succeeded_or_failed}}.

The key observations were {{observations_and_poc_stages}}.

The vulnerability originates in PHP rather than Moodle because {{explanation}}.

I encountered {{problems}} and investigated them using {{troubleshooting_steps}}.

The evidence supports {{conclusion}}, with the following limitations: {{limitations}}.

## 8. Bonus (Optional)

### Bonus 1 — PoC Mechanism (+10%)

I investigated {{poc_stage_or_mechanism}}.

{{mechanism_explanation_and_evidence}}

### Bonus 2 — Additional Impact (+10%)

I explored {{additional_impact}}.

**Confirmed:** {{verified_evidence}}

**Not verified:** {{hypotheses_and_limitations}}

## 9. References

- {{official_advisory}}
- {{poc_repository}}
- {{other_references}}
