Promise = require('promise')
jsrsasign = require 'jsrsasign'

Signature = require './signature'
ConservancyRecord = require './conservancyRecord'
common = require './common'
errors = require './errors'
XML = require './xml'

class Document
  VERSION = '0.0.1'

  constructor: (file, options) ->
    throw new Error('file is required') unless file
    @pdf_content = file
    @signers = []
    @transfers = []
    @lastOStringHash = null
    defaultOpts =
      version: VERSION
      signers: []
      transfers: []
      assetId: null

    @errors = {}
    options = common.extend(defaultOpts, options)
    @assetId = options.assetId
    @conservancyRecord = null
    @recordPresent = false
    if options.conservancyRecord
      @recordPresent = true
      try
        @conservancyRecord = new ConservancyRecord(
          options.conservancyRecord.caCert,
          options.conservancyRecord.userCert,
          options.conservancyRecord.record,
          options.conservancyRecord.timestamp,
          options.conservancyRecord.originalXmlHash
        )
      catch e
        @errors.recordInvalid = "The conservancy record is not valid: #{e.message}"

    @contentType = options.contentType
    @name = options.name
    @version = options.version
    digest = new jsrsasign.crypto.MessageDigest({
      alg: 'sha256',
      prov: 'cryptojs'
    })
    @originalHash = digest.digestHex(@file('hex'))

    doc = this
    if options.signers.length > 0
      options.signers.forEach (el) ->
        doc.addSigner(el)

    if options.transfers.length > 0
      options.transfers.forEach (el) ->
        doc.addTransfer(el)

  fileBuffer: ->
    return null unless @pdf_content
    new Buffer(@pdf_content, 'base64')

  # @deprecated
  pdfBuffer: -> @fileBuffer()

  file: (format) ->
    return null unless @pdf_content
    return common.b64toAscii(@pdf_content) unless format
    return common.b64toHex(@pdf_content) if format is 'hex'
    return @pdf_content if format is 'base64'
    throw new errors.ArgumentError "unknown format #{format}"

  # @deprecated
  pdf: (format) -> @file(format)

  addSigner: (signer) ->
    if !signer.cer || !signer.signedAt
      throw new errors.InvalidSignerError(
        'signer must contain cer and signedAt'
      )
    @signers.push(signer)

  addTransfer: (transfer) ->
    unless transfer instanceof Document
      throw new Error('Transfer must be a Document')
    transfer.parent = this
    if @transfers.length == 0
      transfer.lastOStringHash = this.originalStringHash()
    else
      transfer.lastOStringHash = @transfers.last().originalStringHash()
    @transfers.push(transfer)

  # TODO: set it in addSigner and put it
  #       in a property instead of a function
  signatures: ->
    @signers.map (signer) ->
      new Signature(signer)

  validSignatures: ->
    return false unless @originalHash
    valid = true
    oHash = @originalHash
    @signatures().forEach (signature) ->
      valid = false if valid && !signature.valid(oHash)
    @transfers.forEach (transfer) ->
      valid = transfer.validSignatures()
    valid

  holder: ->
    @signatures().filter((sig) ->
      sig.address
    )[0]

  address: ->
    @holder().address

  certNum: ->
    @holder().certificate.getSerialNumber()

  originalString: ->
    secondArg = @lastOStringHash || @assetId
    os = [
      @originalHash,
      secondArg,
      @address(),
      @certNum()
    ].join('|')

  originalStringHash: -> common.sha256(@originalString())

  validAssetSignatures: ->
    return false unless @originalHash
    valid = true
    oHash = @originalStringHash()
    @signatures().forEach (signature) ->
      valid = false if valid && !signature.validAssetSig(oHash)
    @transfers.forEach (transfer) ->
      valid = transfer.validAssetSignatures()
    valid

  signer_exist: (signer) ->
    selected = @signers.filter (s) ->
      s.email == signer.email ||
        s.cer == signer.cer ||
        s.signature == signer.signature
    selected.length > 0

  @fromXml = (xmlString, validate) ->
    throw new Error('xml is required') unless xmlString
    new Promise (resolve, reject) ->
      XML.parse(xmlString).then (xml) ->
        resolve({
          document: Document.fromXML(xml)
          # hash as attribute in the xml
          xmlOriginalHash: xml.originalHash
        })
      .catch (error) ->
        reject(error)

  # From XMLFiesta::XML
  @fromXML = (xml) ->
    transfers = []
    xml.xmlTransfers().forEach (xmlTransfer) ->
      transfers.push(Document.fromXML(xmlTransfer))

    opts =
      signers: xml.xmlSigners()
      version: xml.version
      name: xml.name
      contentType: xml.contentType
      conservancyRecord: xml.getConservancyRecord()
      transfers: transfers
      assetId: xml.assetId
    new Document(xml.file(), opts)

module.exports = Document
