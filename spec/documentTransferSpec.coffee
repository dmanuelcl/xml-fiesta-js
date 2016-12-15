Document = require '../src/document'
Signature = require '../src/signature'
errors = require '../src/errors'
common = require '../src/common'
fs = require 'fs'

expect = require('expect.js')

describe 'TransferDocument', ->
  describe 'fromXml v1.0.0+', ->
    describe 'with valid xml', ->
      originalHash = 'e1899493f5cea98b4aadece50fb0e' +
                     '08f5523a342cb2925dc50ef604c6d9d7357'
      doc = null
      parsedOHash = null
      beforeEach (done) ->
        xmlExample = "#{__dirname}/fixtures/example_transfer_v1.1.0.xml"
        xml = fs.readFileSync(xmlExample)
        parsedP = Document.fromXml(xml)
        parsedP.then (parsed) ->
          doc = parsed.document
          parsedOHash = parsed.xmlOriginalHash
          done()
        , (err) ->
          console.log('Error', err.stack)
          done()

      it 'should parse the xml', ->
        xmlSigners = doc.signers
        signer = xmlSigners[0]

        expect(doc).to.be.a Document
        expect(doc.pdfBuffer()).not.to.be null
        expect(doc.pdf()).not.to.be null
        expect(doc.originalHash).to.be originalHash
        expect(parsedOHash).to.be originalHash
        expect(xmlSigners).not.to.be.empty()

      describe '.signatures', ->
        it 'should have Signature objects', ->
          expect(doc.signatures()[0]).to.be.a Signature

        it 'should have 2 Signatures', ->
          expect(doc.signatures().length).to.be 2

      describe '.validSignatures', ->
        it 'should be true', ->
          expect(doc.validSignatures()).to.be true

      describe '.validAssetSignatures', ->
        it 'should be true', ->
          expect(doc.validAssetSignatures()).to.be true

      describe '.transfers', ->
        it 'should have 1 transfer', ->
          expect(doc.transfers.length).to.be 1

        describe 'the transfer', ->
          it 'should be a Document', ->
            expect(doc.transfers[0]).to.be.a(Document)

