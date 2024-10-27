{
  pkgs ? import <nixpkgs> { },
}:

let
  decryptSecret =
    { name, value }:
    let
      result =
        pkgs.runCommand "secret-${name}"
          {
            nativeBuildInputs = [
              pkgs.gnupg
              pkgs.coreutils
            ];
            preferLocalBuild = true;
            allowSubstitutes = false;
            HOME = "/build";
            GNUPGHOME = "/build/.gnupg";
            GPG_PASSPHRASE = builtins.getEnv "GPG_PASSPHRASE";
            __structuredAttrs = true;
            outputHashMode = "flat";
            outputHashAlgo = "sha256";
          }
          ''
            # Prompt for passphrase and base64 encode it
            read -s -p "Enter GPG passphrase: " passphrase
            echo

            # Base64 encode the passphrase to handle special characters
            export GPG_PASSPHRASE="$(printf %s "$passphrase")"

            if [ -z "$GPG_PASSPHRASE" ]; then
              echo >&2 "Error: GPG_PASSPHRASE environment variable is not set"
              exit 1
            fi

            mkdir -p $HOME
            mkdir -p $GNUPGHOME
            chmod 700 $GNUPGHOME

            # Create a temporary file for the encrypted data
            ENCRYPTED_FILE=$(mktemp)
            trap 'rm -f $ENCRYPTED_FILE' EXIT

            # Write the encrypted data to a file
            echo "${value}" | tr -d '\n\r' | base64 -d > "$ENCRYPTED_FILE"

            # Configure GPG
            echo "allow-loopback-pinentry" > $GNUPGHOME/gpg-agent.conf
            cat > $GNUPGHOME/gpg.conf <<EOF
                pinentry-mode loopback
                no-tty
                quiet
            EOF

            # Attempt decryption with error output preserved
            if ! (printf '%s\n' "$GPG_PASSPHRASE" | \
                 gpg --batch --passphrase-fd 0 \
                     --decrypt "$ENCRYPTED_FILE" > "$out" 2> gpg_error.log); then
              echo >&2 "GPG Decryption failed for ${name}:"
              cat >&2 gpg_error.log
              exit 1
            fi

            if [ ! -s "$out" ]; then
              echo >&2 "Error: Decrypted value for ${name} is empty"
              exit 1
            fi

            # Debug: Show success
            echo >&2 "Successfully decrypted ${name}"
          '';
    in
    builtins.readFile result;

  decryptSecrets =
    secretsFile:
    let
      secretsJson = builtins.fromJSON (builtins.readFile secretsFile);
      decryptedSecrets = builtins.mapAttrs (
        name: value: decryptSecret { inherit name value; }
      ) secretsJson;
    in
    decryptedSecrets;

in
{
  inherit decryptSecret decryptSecrets;
}
