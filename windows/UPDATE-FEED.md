# Update feed contract

Windows checks a small signed manifest before downloading an installer. The
manifest is deliberately independent of GitHub's API, so the app does not need
an account, a token, or a release tag parser.

## URLs

Primary (GitHub Pages):

```text
https://gabrielzzz.github.io/WattLite/updates/windows.json
https://gabrielzzz.github.io/WattLite/updates/windows.json.sig
```

Fallback (jsDelivr, for networks where Pages is slow):

```text
https://cdn.jsdelivr.net/gh/GabrielZZZ/WattLite@main/docs/updates/windows.json
https://cdn.jsdelivr.net/gh/GabrielZZZ/WattLite@main/docs/updates/windows.json.sig
```

`WATTLITE_UPDATE_MANIFEST` overrides the primary URL for local testing. The
signature URL is the manifest URL plus `.sig`; HTTP is accepted only in this
test mode.

## Manifest

```json
{
  "version": "1.0.1",
  "url": "https://github.com/GabrielZZZ/WattLite/releases/download/v1.0.1-windows/WattLite-1.0.1-windows-x64-setup.exe",
  "mirror": "https://ghfast.top/https://github.com/GabrielZZZ/WattLite/releases/download/v1.0.1-windows/WattLite-1.0.1-windows-x64-setup.exe",
  "sha256": "lowercase 64-character SHA-256 of the setup exe",
  "min_os": "10.0.17763",
  "published": "2026-10-23T00:00:00Z",
  "notes_zh": "optional",
  "notes_en": "optional"
}
```

`url` must be HTTPS. `mirror` is optional. The app tries `url`, then `mirror`,
and verifies SHA-256 before running either.

## Signature

`windows.json.sig` is the base64 encoding of a 64-byte raw ECDSA P-256
signature (`r || s`) over the exact UTF-8 bytes of `windows.json`. The file is
plain base64 text; trim surrounding whitespace before decoding.

- Curve: NIST P-256
- Hash: SHA-256
- Public key: embedded in `windows/WattLite/UpdateService.cs` (`PublicKeyBase64`, 65-byte uncompressed point, base64)
- Private key: `F:\WattLite-secrets\update-signing.pem` on the release machine; never commit it

Tools:

```powershell
dotnet run --project Tools/UpdateSigner -- keygen --out <private.pem> --public-out <public.txt>
dotnet run --project Tools/UpdateSigner -- sign --key <private.pem> --in windows.json --out windows.json.sig
dotnet run --project Tools/UpdateSigner -- verify --public <public.txt> --in windows.json --sig windows.json.sig
```

Release helper (checks that the asset is reachable, writes the manifest, signs it):

```powershell
.\Tools\publish-windows-update.ps1 `
  -Setup .\dist\WattLite-1.0.1-windows-x64-setup.exe `
  -Version 1.0.1 `
  -KeyFile F:\WattLite-secrets\update-signing.pem `
  -NotesZh "修复..." -NotesEn "Fixes..."
```

Publish assets first, then commit and push `docs/updates/windows.json` and
`windows.json.sig`. Otherwise existing apps see an update whose download is
still a 404.

## macOS counterpart

The Mac app uses its own files with the same signature scheme and public key:

```text
docs/updates/macos.json
docs/updates/macos.json.sig
```

Fields: `version` (string, e.g. `"2.2"`), `build` (integer, compares against
CFBundleVersion), `url` (zip), `mirror`, `sha256`, `min_os` (string, e.g.
`"14.0"`), and optional `published`, `notes_zh`, `notes_en`. Verify with
CryptoKit:

```swift
let publicKey = try P256.Signing.PublicKey(x963Representation: publicKeyData)
let signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureData)
let valid = publicKey.isValidSignature(signature, for: manifestData)
```

Keep the same publishing order: upload the zip, write and sign the manifest,
then push the site. The current macOS build is ad-hoc signed, so the updater
should verify the new bundle with `codesign --verify --strict` before replacing
the old one.
