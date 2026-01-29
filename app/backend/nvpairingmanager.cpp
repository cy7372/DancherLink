#include "nvpairingmanager.h"
#include "utils.h"

#include <stdexcept>

#include <openssl/bio.h>
#include <openssl/rand.h>
#include <openssl/pem.h>
#include <openssl/x509.h>
#include <openssl/evp.h>

#include <memory>

// RAII wrappers for OpenSSL objects
struct BioDeleter {
    void operator()(BIO* b) { BIO_free_all(b); }
};
using ScopedBio = std::unique_ptr<BIO, BioDeleter>;

struct X509Deleter {
    void operator()(X509* x) { X509_free(x); }
};
using ScopedX509 = std::unique_ptr<X509, X509Deleter>;

struct EvpPkeyDeleter {
    void operator()(EVP_PKEY* k) { EVP_PKEY_free(k); }
};
using ScopedEvpPkey = std::unique_ptr<EVP_PKEY, EvpPkeyDeleter>;

struct EvpMdCtxDeleter {
    void operator()(EVP_MD_CTX* c) { EVP_MD_CTX_destroy(c); }
};
using ScopedEvpMdCtx = std::unique_ptr<EVP_MD_CTX, EvpMdCtxDeleter>;

struct EvpCipherCtxDeleter {
    void operator()(EVP_CIPHER_CTX* c) { EVP_CIPHER_CTX_free(c); }
};
using ScopedEvpCipherCtx = std::unique_ptr<EVP_CIPHER_CTX, EvpCipherCtxDeleter>;

#define REQUEST_TIMEOUT_MS 5000

NvPairingManager::NvPairingManager(NvComputer* computer) :
    m_Http(computer)
{
    QByteArray cert = IdentityManager::get()->getCertificate();
    ScopedBio bio(BIO_new_mem_buf(cert.data(), -1));
    THROW_BAD_ALLOC_IF_NULL(bio);

    m_Cert = PEM_read_bio_X509(bio.get(), nullptr, nullptr, nullptr);
    if (m_Cert == nullptr)
    {
        throw std::runtime_error("Unable to load certificate");
    }

    QByteArray pk = IdentityManager::get()->getPrivateKey();
    bio.reset(BIO_new_mem_buf(pk.data(), -1));
    THROW_BAD_ALLOC_IF_NULL(bio);

    m_PrivateKey = PEM_read_bio_PrivateKey(bio.get(), nullptr, nullptr, nullptr);
    if (m_PrivateKey == nullptr)
    {
        throw std::runtime_error("Unable to load private key");
    }
}

NvPairingManager::~NvPairingManager()
{
    X509_free(m_Cert);
    EVP_PKEY_free(m_PrivateKey);
}

QByteArray
NvPairingManager::generateRandomBytes(int length)
{
    QByteArray data(length, 0);
    RAND_bytes(reinterpret_cast<unsigned char*>(data.data()), length);
    return data;
}

QByteArray
NvPairingManager::encrypt(const QByteArray& plaintext, const QByteArray& key)
{
    QByteArray ciphertext(plaintext.size(), 0);
    int ciphertextLen;

    ScopedEvpCipherCtx cipher(EVP_CIPHER_CTX_new());
    THROW_BAD_ALLOC_IF_NULL(cipher);

    EVP_EncryptInit(cipher.get(), EVP_aes_128_ecb(), reinterpret_cast<const unsigned char*>(key.data()), NULL);
    EVP_CIPHER_CTX_set_padding(cipher.get(), 0);

    EVP_EncryptUpdate(cipher.get(),
                      reinterpret_cast<unsigned char*>(ciphertext.data()),
                      &ciphertextLen,
                      reinterpret_cast<const unsigned char*>(plaintext.data()),
                      plaintext.length());
    Q_ASSERT(ciphertextLen == ciphertext.length());

    return ciphertext;
}

QByteArray
NvPairingManager::decrypt(const QByteArray& ciphertext, const QByteArray& key)
{
    QByteArray plaintext(ciphertext.size(), 0);
    int plaintextLen;

    ScopedEvpCipherCtx cipher(EVP_CIPHER_CTX_new());
    THROW_BAD_ALLOC_IF_NULL(cipher);

    EVP_DecryptInit(cipher.get(), EVP_aes_128_ecb(), reinterpret_cast<const unsigned char*>(key.data()), NULL);
    EVP_CIPHER_CTX_set_padding(cipher.get(), 0);

    EVP_DecryptUpdate(cipher.get(),
                      reinterpret_cast<unsigned char*>(plaintext.data()),
                      &plaintextLen,
                      reinterpret_cast<const unsigned char*>(ciphertext.data()),
                      ciphertext.length());
    Q_ASSERT(plaintextLen == plaintext.length());

    return plaintext;
}

QByteArray
NvPairingManager::getSignatureFromPemCert(const QByteArray& certificate)
{
#if (OPENSSL_VERSION_NUMBER < 0x10100000L)
    ScopedBio bio(BIO_new_mem_buf(const_cast<char*>(certificate.data()), -1));
#else
    ScopedBio bio(BIO_new_mem_buf(certificate.data(), -1));
#endif
    THROW_BAD_ALLOC_IF_NULL(bio);

    ScopedX509 cert(PEM_read_bio_X509(bio.get(), nullptr, nullptr, nullptr));

#if (OPENSSL_VERSION_NUMBER < 0x10002000L)
    ASN1_BIT_STRING *asnSignature = cert->signature;
#elif (OPENSSL_VERSION_NUMBER < 0x10100000L)
    ASN1_BIT_STRING *asnSignature;
    X509_get0_signature(&asnSignature, NULL, cert.get());
#else
    const ASN1_BIT_STRING *asnSignature;
    X509_get0_signature(&asnSignature, NULL, cert.get());
#endif

    QByteArray signature(reinterpret_cast<char*>(asnSignature->data), asnSignature->length);

    return signature;
}

bool
NvPairingManager::verifySignature(const QByteArray& data, const QByteArray& signature, const QByteArray& serverCertificate)
{
#if (OPENSSL_VERSION_NUMBER < 0x10100000L)
    ScopedBio bio(BIO_new_mem_buf(const_cast<char*>(serverCertificate.data()), -1));
#else
    ScopedBio bio(BIO_new_mem_buf(serverCertificate.data(), -1));
#endif
    THROW_BAD_ALLOC_IF_NULL(bio);

    ScopedX509 cert(PEM_read_bio_X509(bio.get(), nullptr, nullptr, nullptr));
    if (!cert) {
        return false;
    }

    ScopedEvpPkey pubKey(X509_get_pubkey(cert.get()));
    THROW_BAD_ALLOC_IF_NULL(pubKey);

    ScopedEvpMdCtx mdctx(EVP_MD_CTX_create());
    THROW_BAD_ALLOC_IF_NULL(mdctx);

    EVP_DigestVerifyInit(mdctx.get(), nullptr, EVP_sha256(), nullptr, pubKey.get());
    EVP_DigestVerifyUpdate(mdctx.get(), data.data(), data.length());
    int result = EVP_DigestVerifyFinal(mdctx.get(), reinterpret_cast<unsigned char*>(const_cast<char*>(signature.data())), signature.length());

    return result > 0;
}

QByteArray
NvPairingManager::signMessage(const QByteArray& message)
{
    ScopedEvpMdCtx ctx(EVP_MD_CTX_create());
    THROW_BAD_ALLOC_IF_NULL(ctx);

    EVP_DigestSignInit(ctx.get(), NULL, EVP_sha256(), NULL, m_PrivateKey);
    EVP_DigestSignUpdate(ctx.get(), reinterpret_cast<unsigned char*>(const_cast<char*>(message.data())), message.length());

    size_t signatureLength = 0;
    EVP_DigestSignFinal(ctx.get(), NULL, &signatureLength);

    QByteArray signature((int)signatureLength, 0);
    EVP_DigestSignFinal(ctx.get(), reinterpret_cast<unsigned char*>(signature.data()), &signatureLength);

    return signature;
}

QByteArray
NvPairingManager::saltPin(const QByteArray& salt, QString pin)
{
    return QByteArray().append(salt).append(pin.toLatin1());
}

NvPairingManager::PairState
NvPairingManager::pair(QString appVersion, QString pin, QSslCertificate& serverCert)
{
    int serverMajorVersion = NvHTTP::parseQuad(appVersion).at(0);
    qInfo() << "Pairing with server generation:" << serverMajorVersion;

    QCryptographicHash::Algorithm hashAlgo;
    int hashLength;
    if (serverMajorVersion >= 7)
    {
        // Gen 7+ uses SHA-256 hashing
        hashAlgo = QCryptographicHash::Sha256;
        hashLength = 32;
    }
    else
    {
        // Prior to Gen 7 uses SHA-1 hashing
        hashAlgo = QCryptographicHash::Sha1;
        hashLength = 20;
    }

    QByteArray salt = generateRandomBytes(16);
    QByteArray saltedPin = saltPin(salt, pin);

    QByteArray aesKey = QCryptographicHash::hash(saltedPin, hashAlgo).constData();
    aesKey.truncate(16);

    QString getCert = m_Http.openConnectionToString(m_Http.m_BaseUrlHttp,
                                                    "pair",
                                                    "devicename=roth&updateState=1&phrase=getservercert&salt=" +
                                                    salt.toHex() + "&clientcert=" + IdentityManager::get()->getCertificate().toHex(),
                                                    0);
    NvHTTP::verifyResponseStatus(getCert);
    if (NvHTTP::getXmlString(getCert, "paired") != "1")
    {
        qCritical() << "Failed pairing at stage #1";
        return PairState::FAILED;
    }

    QByteArray serverCertStr = NvHTTP::getXmlStringFromHex(getCert, "plaincert");
    if (serverCertStr == nullptr)
    {
        qCritical() << "Server likely already pairing";
        m_Http.openConnectionToString(m_Http.m_BaseUrlHttp, "unpair", nullptr, REQUEST_TIMEOUT_MS);
        return PairState::ALREADY_IN_PROGRESS;
    }

    QSslCertificate unverifiedServerCert = QSslCertificate(serverCertStr);
    if (unverifiedServerCert.isNull()) {
        Q_ASSERT(!unverifiedServerCert.isNull());

        qCritical() << "Failed to parse plaincert";
        m_Http.openConnectionToString(m_Http.m_BaseUrlHttp, "unpair", nullptr, REQUEST_TIMEOUT_MS);
        return PairState::FAILED;
    }

    // Pin this cert for TLS until pairing is complete. If successful, we will propagate
    // the cert into the NvComputer object and persist it.
    m_Http.setServerCert(unverifiedServerCert);

    QByteArray randomChallenge = generateRandomBytes(16);
    QByteArray encryptedChallenge = encrypt(randomChallenge, aesKey);
    QString challengeXml = m_Http.openConnectionToString(m_Http.m_BaseUrlHttp,
                                                         "pair",
                                                         "devicename=roth&updateState=1&clientchallenge=" +
                                                         encryptedChallenge.toHex(),
                                                         REQUEST_TIMEOUT_MS);
    NvHTTP::verifyResponseStatus(challengeXml);
    if (NvHTTP::getXmlString(challengeXml, "paired") != "1")
    {
        qCritical() << "Failed pairing at stage #2";
        m_Http.openConnectionToString(m_Http.m_BaseUrlHttp, "unpair", nullptr, REQUEST_TIMEOUT_MS);
        return PairState::FAILED;
    }

    QByteArray challengeResponseData = decrypt(m_Http.getXmlStringFromHex(challengeXml, "challengeresponse"), aesKey);
    QByteArray clientSecretData = generateRandomBytes(16);
    QByteArray challengeResponse;
    QByteArray serverResponse(challengeResponseData.data(), hashLength);

#if (OPENSSL_VERSION_NUMBER < 0x10002000L)
    ASN1_BIT_STRING *asnSignature = m_Cert->signature;
#elif (OPENSSL_VERSION_NUMBER < 0x10100000L)
    ASN1_BIT_STRING *asnSignature;
    X509_get0_signature(&asnSignature, NULL, m_Cert);
#else
    const ASN1_BIT_STRING *asnSignature;
    X509_get0_signature(&asnSignature, NULL, m_Cert);
#endif

    challengeResponse.append(challengeResponseData.data() + hashLength, 16);
    challengeResponse.append(reinterpret_cast<char*>(asnSignature->data), asnSignature->length);
    challengeResponse.append(clientSecretData);

    QByteArray paddedHash = QCryptographicHash::hash(challengeResponse, hashAlgo);
    paddedHash.resize(32);
    QByteArray encryptedChallengeResponseHash = encrypt(paddedHash, aesKey);
    QString respXml = m_Http.openConnectionToString(m_Http.m_BaseUrlHttp,
                                                    "pair",
                                                    "devicename=roth&updateState=1&serverchallengeresp=" +
                                                    encryptedChallengeResponseHash.toHex(),
                                                    REQUEST_TIMEOUT_MS);
    NvHTTP::verifyResponseStatus(respXml);
    if (NvHTTP::getXmlString(respXml, "paired") != "1")
    {
        qCritical() << "Failed pairing at stage #3";
        m_Http.openConnectionToString(m_Http.m_BaseUrlHttp, "unpair", nullptr, REQUEST_TIMEOUT_MS);
        return PairState::FAILED;
    }

    QByteArray pairingSecret = NvHTTP::getXmlStringFromHex(respXml, "pairingsecret");
    QByteArray serverSecret = pairingSecret.left(16);
    QByteArray serverSignature = pairingSecret.mid(16);

    if (!verifySignature(serverSecret,
                         serverSignature,
                         serverCertStr))
    {
        qCritical() << "MITM detected";
        m_Http.openConnectionToString(m_Http.m_BaseUrlHttp, "unpair", nullptr, REQUEST_TIMEOUT_MS);
        return PairState::FAILED;
    }

    QByteArray expectedResponseData;
    expectedResponseData.append(randomChallenge);
    expectedResponseData.append(getSignatureFromPemCert(serverCertStr));
    expectedResponseData.append(serverSecret);
    if (QCryptographicHash::hash(expectedResponseData, hashAlgo) != serverResponse)
    {
        qCritical() << "Incorrect PIN";
        m_Http.openConnectionToString(m_Http.m_BaseUrlHttp, "unpair", nullptr, REQUEST_TIMEOUT_MS);
        return PairState::PIN_WRONG;
    }

    QByteArray clientPairingSecret;
    clientPairingSecret.append(clientSecretData);
    clientPairingSecret.append(signMessage(clientSecretData));

    QString secretRespXml = m_Http.openConnectionToString(m_Http.m_BaseUrlHttp,
                                                          "pair",
                                                          "devicename=roth&updateState=1&clientpairingsecret=" +
                                                          clientPairingSecret.toHex(),
                                                          REQUEST_TIMEOUT_MS);
    NvHTTP::verifyResponseStatus(secretRespXml);
    if (NvHTTP::getXmlString(secretRespXml, "paired") != "1")
    {
        qCritical() << "Failed pairing at stage #4";
        m_Http.openConnectionToString(m_Http.m_BaseUrlHttp, "unpair", nullptr, REQUEST_TIMEOUT_MS);
        return PairState::FAILED;
    }

    QString pairChallengeXml = m_Http.openConnectionToString(m_Http.m_BaseUrlHttps,
                                                             "pair",
                                                             "devicename=roth&updateState=1&phrase=pairchallenge",
                                                             REQUEST_TIMEOUT_MS);
    NvHTTP::verifyResponseStatus(pairChallengeXml);
    if (NvHTTP::getXmlString(pairChallengeXml, "paired") != "1")
    {
        qCritical() << "Failed pairing at stage #5";
        m_Http.openConnectionToString(m_Http.m_BaseUrlHttp, "unpair", nullptr, REQUEST_TIMEOUT_MS);
        return PairState::FAILED;
    }

    serverCert = std::move(unverifiedServerCert);
    return PairState::PAIRED;
}
