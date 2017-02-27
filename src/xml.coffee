Promise = require('promise')
xml2js = require('xml2js')
xmlCrypto = require('xml-crypto')
select = require('xpath.js')
Dom = require('xmldom').DOMParser

ExclusiveCanonicalization = xmlCrypto.
                            SignedXml.
                            CanonicalizationAlgorithms['http://www.w3.org/2001/10/xml-exc-c14n#']

common = require './common'

class XML
  @parse: (xml) ->
    new Promise (resolve, reject) ->
      xml2js.parseString xml, (err, result) ->
        return reject(err) if err
        xml = XML.parseJs(result)
        resolve(xml)

  # Parse a xml2js Javascript Object
  # @param xmlObject [Hash] xml2js Javascript Object
  # @param transfer [Boolean] is this document a transfer?
  @parseJs: (xmlObject, transfer) ->
    xml = new XML
    if transfer
      xml.eDocument = xmlObject
    else
      xml.eDocument = xmlObject.electronicDocument || xmlObject.transferableDocument
    eDocumentAttrs = xml.eDocument.$
    xml.version = eDocumentAttrs.version
    xml.signed = eDocumentAttrs.signed
    xml.assetId = eDocumentAttrs.assetId
    v = xml.version.split(/\./).map (v) -> parseInt(v)
    xml.version_int = v[0] * 100 + v[1] * 10 + v[2]

    if xml.version_int < 100
      xml.fileElementName = 'pdf'
    else
      xml.fileElementName = 'file'

    pdfAttrs = xml.eDocument[xml.fileElementName][0].$
    xml.name = pdfAttrs.name
    xml.contentType = pdfAttrs.contentType
    xml.originalHash = pdfAttrs.originalHash
    xml

  canonical: ->
    edoc = JSON.parse(JSON.stringify(@eDocument))
    if edoc.conservancyRecord
      delete edoc.conservancyRecord
    if @version_int >= 100
      edoc[@fileElementName][0]._ = ''

    # TODO: set 'transferableDocument' when its a transferable
    builder = new xml2js.Builder(
      rootName: 'electronicDocument'
      renderOpts:
        pretty: false
    )
    originalXml = builder.buildObject(edoc)

    doc = new Dom().parseFromString(originalXml)
    elem = select(doc, "//*")[0]
    can = new ExclusiveCanonicalization()
    can.process(elem).toString()

  file: ->
    @eDocument[@fileElementName][0]._

  pdf: -> @file()

  xmlSigners: ->
    parsedSigners = []
    signers = @eDocument.signers
    signers[0].signer.forEach (signer) ->
      attrs = signer.$
      parsedSigners.push({
        taxId: attrs.id
        email: attrs.email
        cer: common.b64toHex(signer.certificate[0]._)
        signature: signer.signature && common.b64toHex(signer.signature[0]._)
        assetSignature: signer.assetSignature && common.b64toHex(signer.assetSignature[0]._)
        signedAt: signer.signature && signer.signature[0].$.signedAt
        address: attrs.address
      })
    parsedSigners

  xmlTransfers: ->
    return [] unless @eDocument.transfers
    parsedTransfers = []
    @eDocument.transfers[0].transfer.forEach (transfer) ->
      parsedTransfers.push(XML.parseJs(transfer, true))
    parsedTransfers

  getConservancyRecord: ->
    return null unless @eDocument.conservancyRecord
    cr = @eDocument.conservancyRecord[0]
    {
      caCert: cr.caCertificate[0]._
      userCert: cr.userCertificate[0]._
      record: cr.record[0]
      timestamp: cr.$.timestamp
      originalXmlHash: common.sha256(@canonical())
    }

module.exports = XML
