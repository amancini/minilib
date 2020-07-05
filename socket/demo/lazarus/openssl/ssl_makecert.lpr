program ssl_makecert;
{**
 *  This file is part of the "MiniLib"/Sockets
 *
 * @license   Mit
 * @author    Zaher Dirkey zaherdirkey
 *
 *}
{$mode delphi}{$H+}

//I mixed of 2 of example
//https://github.com/irtimmer/moonlight-embedded/blob/master/libgamestream/mkcert.c
//http://www.opensource.apple.com/source/OpenSSL/OpenSSL-22/openssl/demos/x509/mkcert.c

{
  Testing
    https://www.sslshopper.com/certificate-key-matcher.html
}

uses
  SysUtils, Classes, mnOpenSSLAPI, mnLibraries;

function AddExt(cert: PX509; nid: integer; value: pchar): Integer;
var
  ex: PX509_EXTENSION;
  ctx: TX509V3_CTX;
begin
	// This sets the 'context' of the extensions.
	// No configuration database
  X509V3_set_ctx_nodb(@ctx);

	{ Issuer and subject certs: both the target since it is self signed,
	  no request and no CRL
   }
	X509V3_set_ctx(@ctx, cert, cert, nil, nil, 0);
  ex := X509V3_EXT_conf_nid(nil, @ctx, nid, value);

	if (ex = nil) then
		exit(0);

  X509_add_ext(cert, ex, -1);
  X509_EXTENSION_free(ex);
  exit(1);
end;

//TODO need to make more clean when exit, some objects most not freed if assigned successed
function MakeCert(var x509p: PX509; var pkeyp: PEVP_PKEY; C, CN: string; Bits: Integer; Serial: Integer; Years: Integer): Boolean;
var
  x: PX509 = nil;
  pk: PEVP_PKEY = nil;
  rsa: PRSA = nil;
  name: PX509_NAME = nil;
  bne: PBIGNUM = nil;
  sign: PX509_sign = nil;
  res: Integer;
begin
  try
	  if (pkeyp = nil) then
    begin
      pk := EVP_PKEY_new();
		  if (pk = nil) then
      begin
			  exit(False);
      end
    end
	  else
      pk := pkeyp;

	  if (x509p = nil) then
    begin
      x := X509_new();
		  if (x = nil) then
        exit(False);
    end
	  else
		  x := x509p;

    rsa := RSA_new();

    if (rsa = nil) then
      exit(False);

    bne := BN_new();
    if (bne = nil) then
      exit(False);

    BN_set_word(bne, RSA_F4);

    res := RSA_generate_key_ex(rsa, bits, bne, nil);

    if (res = 0) then
      exit(False);

    res := EVP_PKEY_assign_RSA(pk, rsa);
    if (res = 0) then
      exit(False);

    X509_set_version(x, 2);

    ASN1_INTEGER_set(X509_get_serialNumber(x), serial);
    X509_gmtime_adj(X509_getm_notBefore(x), 0);
    X509_gmtime_adj(X509_getm_notAfter(x), 60 * 60 * 24 * 365 * Years);

    X509_set_pubkey(x, pk);
    name := X509_get_subject_name(x);

    (* This function creates and adds the entry, working out the
     * correct string type and performing checks on its length.
     *)
 	  X509_NAME_add_entry_by_txt(name, 'C', MBSTRING_ASC, PByte(C), -1, -1, 0);
    X509_NAME_add_entry_by_txt(name, 'CN', MBSTRING_ASC, PByte(CN), -1, -1, 0);

    (* Its self signed so set the issuer name to be the same as the
     * subject.
     *)
    X509_set_issuer_name(x, name);

    (* Add various extensions: standard extensions *)

    AddExt(x, NID_basic_constraints, 'critical,CA:TRUE');
    AddExt(x, NID_key_usage, PChar('critical,digitalSignature,keyEncipherment'));
    AddExt(x, NID_subject_key_identifier, 'hash');

    sign := X509_sign(x, pk, EVP_sha256());
    if (sign = nil) then
      exit(False);
    x509p := x;
    pkeyp := pk;
    exit(True);
  finally
    if not Result then
    begin
      if x <> nil then
    	  X509_free(x);
      if pk <> nil then
    	  EVP_PKEY_free(pk);
    end;
  end;
end;

var
  s: string;
	x509: PX509 = nil;
	pkey: PEVP_PKEY = nil;
  //rsa: PRSA;
  outbio: PBIO;
begin
  try
    OpenSSLLib.Load;
    CryptoLib.Load;
    OPENSSL_init_ssl(0, nil);
    OPENSSL_init_crypto(0, nil);

    CRYPTO_mem_ctrl(CRYPTO_MEM_CHECK_ON);
    //bio_err := BIO_new_fp(stderr, BIO_NOCLOSE);
    MakeCert(x509, pkey, 'SY', 'Just an Example', 2048, 0, 1);
    {
      rsa := EVP_PKEY_get0_RSA(pkey);
      BIO_puts(outbio, 'RSA'#13#10);
      RSA_print(outbio, rsa, 0);
    }
    outbio := BIO_new_file(PChar('test.key'), 'w');
  	PEM_write_bio_PrivateKey(outbio, pkey, nil, nil, 0, nil, nil);
    BIO_free(outbio);

    outbio := BIO_new_file(PChar('test.cert'), 'w');
  	PEM_write_bio_X509(outbio, x509);
    BIO_free(outbio);

    WriteLn('Done, check output file');
  finally
    if x509 <> nil then
  	  X509_free(x509);
    if pkey <> nil then
  	  EVP_PKEY_free(pkey);
    WriteLn('Press Enter to exit');
    while true do
    begin
      ReadLn(s);
      if s <> '' then
        WriteLn('I said Enter')
      else
        break;
    end;
   end;
end.