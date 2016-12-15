Certificate = require './certificate'
errors = require './errors'
common = require './common'

class Signature
  constructor: (args) ->
    cer = args.cer
    @signature = args.signature
    @assetSignature = args.assetSignature
    @signedAt = args.signedAt
    @email = args.email
    @address = args.address
    throw new errors.ArgumentError(
      'Signature must have signedAt'
    ) unless @signedAt
    throw new errors.ArgumentError(
      'Signature must have cer'
    ) unless cer

    @certificate = new Certificate(false, cer)
    @email ?= @certificate.email()

    @signer = {
      id: @certificate.owner_id(),
      name: @certificate.owner(),
      email: @email
    }

  sig: (format) ->
    return false unless @signature
    return @signature if format is 'hex' or !format
    return common.hextoB64(@signature) if format is 'base64'
    throw new errors.ArgumentError "unknown format #{format}"

  valid: (hash) ->
    throw new errors.ArgumentError 'hash is required' unless hash
    @certificate.verifyString(hash, @signature)

  validAssetSig: (hash) ->
    throw new errors.ArgumentError 'hash is required' unless hash
    @certificate.verifyString(hash, @assetSignature)

module.exports = Signature
