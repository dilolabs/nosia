require "openssl"

module CaddyCertificateFixtures
  def certificate_fixture(kind = :root)
    @certificate_fixtures ||= {}
    @certificate_fixtures[kind] ||= build_certificate_fixture(kind)
  end

  private
    def build_certificate_fixture(kind)
      case kind
      when :reissued_root
        certificate_fixture(:root)
        @certificate_fixtures.fetch(:reissued_root)
      when :multiple
        certificate_fixture(:root) + certificate_fixture(:leaf)
      when :private_key
        certificate_fixture(:root) + "-----BEGIN PRIVATE KEY-----\nNOT A REAL KEY\n-----END PRIVATE KEY-----\n"
      when :malformed
        "-----BEGIN CERTIFICATE-----\nnot a certificate\n-----END CERTIFICATE-----\n"
      when :trailing_text
        certificate_fixture(:root) + "untrusted trailing material\n"
      else
        build_certificate(kind).to_pem
      end
    end

    def build_certificate(kind)
      key = OpenSSL::PKey::EC.generate("prime256v1")
      certificate = OpenSSL::X509::Certificate.new
      certificate.version = 2
      certificate.serial = OpenSSL::BN.rand(128).to_i
      certificate.subject = OpenSSL::X509::Name.parse("/CN=Ephemeral Caddy fixture CA:TRUE")
      certificate.issuer = kind == :other_issuer ? OpenSSL::X509::Name.parse("/CN=Different issuer") : certificate.subject
      certificate.public_key = key
      certificate.not_before = Time.now - (kind == :future ? -3600 : 3600)
      certificate.not_after = Time.now + (kind == :expired ? -60 : 86_400)

      extensions = OpenSSL::X509::ExtensionFactory.new
      extensions.subject_certificate = certificate
      extensions.issuer_certificate = certificate
      unless kind == :no_basic_constraints
        certificate.add_extension(extensions.create_extension("basicConstraints", kind == :leaf ? "CA:FALSE" : "CA:TRUE", true))
      end
      certificate.add_extension(extensions.create_extension("keyUsage", "keyCertSign,cRLSign", true))
      signer = kind == :bad_self_signature ? OpenSSL::PKey::EC.generate("prime256v1") : key
      certificate.sign(signer, OpenSSL::Digest.new("SHA256"))
      if kind == :root
        reissued = certificate.dup
        reissued.serial += 1
        reissued.sign(key, OpenSSL::Digest.new("SHA256"))
        @certificate_fixtures[:reissued_root] = reissued.to_pem
      end
      certificate
    end
end
