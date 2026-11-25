require 'rails_helper'

RSpec.describe SiteKeys::Cipher do
  let(:user) { create(:user) }
  let(:private_key) { SecureRandom.random_bytes(32) }

  subject(:cipher) { described_class.new(user) }

  describe '#unwrap' do
    let(:wrap) { cipher.wrap(private_key, 'a secret') }

    it 'returns the key for the secret it was wrapped under' do
      expect(cipher.unwrap(wrap, 'a secret')).to eq(private_key)
    end

    it 'raises a mismatch error for another secret' do
      expect { cipher.unwrap(wrap, 'another secret') }.to raise_error(SiteKeys::MismatchError)
    end

    it 'raises an encryption error for a malformed wrap' do
      expect { cipher.unwrap('not json', 'a secret') }
        .to raise_error(Encryption::EncryptionError) do |err|
          expect(err).not_to be_a(SiteKeys::MismatchError)
        end
    end

    it 'does not keep the plaintext key in the wrap' do
      expect(wrap).not_to include(Base64.strict_encode64(private_key))
    end

    it 'uses the site-key-encryption KMS context instead of pii-encryption' do
      user
      kms_client = instance_double(Encryption::KmsClient)
      allow(Encryption::KmsClient).to receive(:new).and_return(kms_client)
      expect(kms_client).to receive(:encrypt)
        .with(anything, { 'context' => 'site-key-encryption', 'user_uuid' => user.uuid })
        .and_return('kms_wrapped')

      cipher.wrap(private_key, 'a secret')
    end

    it 'rejects a wrap encrypted under the pii-encryption KMS context' do
      pii_wrap = Encryption::Encryptors::PiiEncryptor.new('a secret').encrypt(
        Base64.strict_encode64(private_key),
        user_uuid: user.uuid,
      )

      expect { cipher.unwrap(pii_wrap, 'a secret') }
        .to raise_error(Encryption::EncryptionError)
    end
  end
end
