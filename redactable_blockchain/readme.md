# Complying with the Right to Be Forgotten in Smart Mobility Data Sharing: A Delete-Only Redactable Consortium Blockchain

This folder includes a prototype for a delete-only redactable blockchain system proposed in the conference paper: 

Tironsakkul, Tin, et al. "Complying with the Right to Be Forgotten in Smart Mobility Data Sharing: A Delete-Only Redactable Consortium Blockchain." SECRYPT 2026: 23rd International Conference on Security and Cryptography.

The model has the following features:

- Meta-transaction + ECDSA digital signature approach.
- Schnorr-based accountable threshold signature (ATS) for secure and efficient redaction.
- Expands the ATS scheme to store a public key index for storage efficiency (ATS-IQ).
- Allows multiple transaction redactions per redaction request.

This prototype does not include a consensus mechanism since the modified blockchain protocol does not affect any of the inherent blockchain network mechanisms.
