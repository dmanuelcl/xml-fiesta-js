const Promise = require('promise');
const xmlCrypto = require('xml-crypto');
const select = require('xpath.js');
const Dom = require('xmldom').DOMParser;

import { parseString, Builder } from 'xml2js';
import { b64toHex, sha256 } from './common';

const ExclusiveCanonicalization = xmlCrypto.
                            SignedXml.
                            CanonicalizationAlgorithms['http://www.w3.org/2001/10/xml-exc-c14n#'];

export default class XML {
  eDocument: any;
  signed: boolean;
  version: any;
  version_int: any;
  fileElementName: any;
  encrypted: any;
  name: any;
  contentType: any;
  originalHash: any;

  static parse(string) {
    const xml = new XML();
    return xml.parse(string);
  }

  static toXML(eDocument: any, file: string) {
    const edoc = JSON.parse(JSON.stringify(eDocument));
    this.removeEncrypedData(edoc)
    edoc.file[0]._ = file;

    const builder = new Builder({
      rootName: 'electronicDocument',
      renderOpts: {
        pretty: false
      }
    });
    return builder.buildObject(edoc);
  }

  static removeEncrypedData(xmljs: any) {
    if (xmljs.file && xmljs.file[0]) {
      delete xmljs.file[0].$.encrypted;
      xmljs.file[0].$.name = xmljs.file[0].$.name.replace('.enc', '');
    }
    xmljs.signers[0].signer.forEach(function(signer) {
      delete signer.ePass;
    });
  }

  parse(xml) {
    const el = this;
    return new Promise((resolve, reject) => parseString(xml, function(err, result) {
      if (err) { return reject(err); }
      el.eDocument = result.electronicDocument;
      const eDocumentAttrs = el.eDocument.$;
      el.version = eDocumentAttrs.version;
      el.signed = eDocumentAttrs.signed;
      const v = el.version.split(/\./).map(v => parseInt(v));
      el.version_int = (v[0] * 100) + (v[1] * 10) + v[2];

      if (el.version_int < 100) {
        el.fileElementName = 'pdf';
      } else {
        el.fileElementName = 'file';
      }

      const pdfAttrs = el.eDocument[el.fileElementName][0].$;
      el.encrypted = pdfAttrs.encrypted;
      el.name = pdfAttrs.name;
      el.contentType = pdfAttrs.contentType;
      el.originalHash = pdfAttrs.originalHash;
      return resolve(el);
    }));
  }

  canonical() {
    const edoc = JSON.parse(JSON.stringify(this.eDocument));
    delete edoc.conservancyRecord;
    XML.removeEncrypedData(edoc);

    if (this.version_int >= 100) {
      edoc[this.fileElementName][0]._ = '';
    }

    const builder = new Builder({
      rootName: 'electronicDocument',
      renderOpts: {
        pretty: false
      }
    });
    const originalXml = builder.buildObject(edoc);

    const doc = new Dom().parseFromString(originalXml);
    const elem = select(doc, "//*")[0];
    const can = new ExclusiveCanonicalization();
    const canonicalString = can.process(elem).toString();
    // remove windows line-endings
    // fixes an issue when users save the XML in windows
    return canonicalString.replace(/&#xD;/g, '');
  }

  file() {
    return this.eDocument[this.fileElementName][0]._;
  }

  pdf() { return this.file(); }

  xmlSigners() {
    const parsedSigners = [];
    this.eDocument.signers[0].signer.forEach(function(signer) {
      const attrs = signer.$;
      const xmlSigner: any = {
        email: attrs.email,
        cer: b64toHex(signer.certificate[0]._),
        signature: b64toHex(signer.signature[0]._),
        signedAt: signer.signature[0].$.signedAt,
      };
      if (signer.ePass){
        xmlSigner.ePass = {
          content: b64toHex(signer.ePass[0]._),
          algorithm: signer.ePass[0].$.algorithm,
          iterations: signer.ePass[0].$.iterations,
          keySize: signer.ePass[0].$.keySize,
        }
      }
      return parsedSigners.push(xmlSigner);
    });
    return parsedSigners;
  }

  getConservancyRecord() {
    let crVersion, userCertificate;
    if (!this.eDocument.conservancyRecord) { return null; }
    const cr = this.eDocument.conservancyRecord[0];
    if (!cr.$.version) {
      userCertificate = cr.userCertificate[0]._;
    } else {
      crVersion = cr.$.version;
    }

    return {
      caCert: cr.caCertificate[0]._,
      userCert: userCertificate,
      record: cr.record[0],
      timestamp: cr.$.timestamp,
      originalXmlHash: sha256(this.canonical()),
      version: crVersion
    };
  }
}
