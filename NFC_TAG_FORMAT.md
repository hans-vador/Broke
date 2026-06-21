# Broke NFC Tag Format

## Production Payload

Each physical tag receives one unique versioned identifier:

```text
broke://tag/v1/550e8400-e29b-41d4-a716-446655440000
```

- `broke` is the product URI scheme.
- `tag` identifies this as an NFC tag credential.
- `v1` is the payload format version.
- The final component is a randomly generated UUID v4 unique to that tag.

The tag does not contain a user's app selection, lock state, name, account
details, or BLE pod information.

## NDEF Encoding

The preferred production encoding is one NDEF URI record:

- Type Name Format: NFC Well Known
- Type: `U` (`0x55`)
- URI prefix byte: `0x00` (no abbreviation)
- URI: the complete `broke://tag/v1/<uuid>` value

For pilot provisioning, the app also accepts the same value in an NDEF Text
record. Production tags should consistently use the URI record.

## Provisioning

1. Generate a cryptographically random UUID v4 for each tag.
2. Write the complete versioned URI as an NDEF URI record.
3. Record the tag ID in manufacturing inventory if replacement tracking is
   required.
4. Verify the record can be read.
5. Optionally make the tag read-only after verification.

The app pairs by reading and storing the complete canonical URI. Later scans
must contain the same URI to toggle the NFC lock.

Standard NDEF tags can be cloned. A future anti-cloning design should use
cryptographic tags and server-verified dynamic authentication instead of
treating the UUID as a secret.
