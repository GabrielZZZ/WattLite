using System.Security.Cryptography;
using System.Text;

if (args.Length == 0 || args[0] is "-h" or "--help")
{
    Usage();
    return 0;
}

try
{
    return args[0] switch
    {
        "keygen" => Keygen(args),
        "sign" => Sign(args),
        "verify" => Verify(args),
        _ => Unknown(args[0])
    };
}
catch (Exception ex)
{
    Console.Error.WriteLine($"error: {ex.Message}");
    return 1;
}

static int Keygen(string[] args)
{
    var outPath = Required(args, "--out");
    var publicOut = Optional(args, "--public-out");

    using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
    var pem = key.ExportPkcs8PrivateKeyPem();
    var full = Path.GetFullPath(outPath);
    Directory.CreateDirectory(Path.GetDirectoryName(full)!);
    File.WriteAllText(full, pem, new UTF8Encoding(false));

    var publicKey = PublicKeyBase64(key);
    if (publicOut is not null)
    {
        var publicFull = Path.GetFullPath(publicOut);
        Directory.CreateDirectory(Path.GetDirectoryName(publicFull)!);
        File.WriteAllText(publicFull, publicKey + "\n", new UTF8Encoding(false));
    }

    Console.WriteLine($"Private key: {full}");
    Console.WriteLine("Keep this file offline and backed up; it must never enter the repository.");
    Console.WriteLine($"Public key (x963, base64): {publicKey}");
    return 0;
}

static int Sign(string[] args)
{
    var keyPath = Required(args, "--key");
    var inputPath = Required(args, "--in");
    var outputPath = Required(args, "--out");

    using var key = ECDsa.Create();
    key.ImportFromPem(File.ReadAllText(keyPath));
    var payload = File.ReadAllBytes(inputPath);
    // raw r||s, matching CryptoKit's P256.Signing.ECDSASignature(rawRepresentation:)
    var signature = key.SignData(payload, HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation);
    File.WriteAllText(outputPath, Convert.ToBase64String(signature) + "\n", new UTF8Encoding(false));

    Console.WriteLine($"Signed {inputPath}");
    Console.WriteLine($"Signature: {outputPath}");
    return 0;
}

static int Verify(string[] args)
{
    var publicArg = Required(args, "--public");
    var inputPath = Required(args, "--in");
    var signaturePath = Required(args, "--sig");

    var publicKey = File.Exists(publicArg) ? File.ReadAllText(publicArg).Trim() : publicArg.Trim();
    using var key = ImportPublicKey(publicKey);
    var payload = File.ReadAllBytes(inputPath);
    var signature = Convert.FromBase64String(File.ReadAllText(signaturePath).Trim());
    var valid = key.VerifyData(payload, signature, HashAlgorithmName.SHA256,
        DSASignatureFormat.IeeeP1363FixedFieldConcatenation);

    Console.WriteLine(valid ? "VALID" : "INVALID");
    return valid ? 0 : 1;
}

static ECDsa ImportPublicKey(string base64)
{
    var raw = Convert.FromBase64String(base64);
    if (raw.Length != 65 || raw[0] != 0x04)
        throw new InvalidDataException("Expected a 65-byte uncompressed P-256 public key (0x04 || X || Y).");

    var x = raw.AsSpan(1, 32).ToArray();
    var y = raw.AsSpan(33, 32).ToArray();
    return ECDsa.Create(new ECParameters
    {
        Curve = ECCurve.NamedCurves.nistP256,
        Q = new ECPoint { X = x, Y = y }
    });
}

static string PublicKeyBase64(ECDsa key)
{
    var p = key.ExportParameters(false);
    var x = p.Q.X ?? throw new InvalidOperationException("public key has no X coordinate");
    var y = p.Q.Y ?? throw new InvalidOperationException("public key has no Y coordinate");
    var raw = new byte[65];
    raw[0] = 0x04;
    x.CopyTo(raw, 1 + (32 - x.Length));
    y.CopyTo(raw, 33 + (32 - y.Length));
    return Convert.ToBase64String(raw);
}

static string Required(string[] args, string name)
{
    var value = Optional(args, name);
    return value ?? throw new ArgumentException($"missing {name}");
}

static string? Optional(string[] args, string name)
{
    for (var i = 1; i < args.Length - 1; i++)
        if (args[i] == name) return args[i + 1];
    return null;
}

static int Unknown(string command)
{
    Console.Error.WriteLine($"error: unknown command '{command}'");
    Usage();
    return 1;
}

static void Usage()
{
    Console.WriteLine("""
        WattLite update signer (ECDSA P-256, SHA-256)

          keygen --out <private.pem> [--public-out <public.txt>]
          sign   --key <private.pem> --in <windows.json> --out <windows.json.sig>
          verify --public <public.txt|base64> --in <windows.json> --sig <windows.json.sig>

        Signatures are base64-encoded raw r||s (64 bytes), so CryptoKit can verify
        them directly with P256.Signing.ECDSASignature(rawRepresentation:).
        """);
}
