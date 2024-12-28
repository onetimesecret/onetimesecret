// tests/unit/vue/fixtures/metadata.spec.ts
import { MetadataState } from '@/schemas/models/metadata';
import { SecretState } from '@/schemas/models/secret';
import { describe, expect, it } from 'vitest';

import {
  mockBurnedMetadataRecord,
  mockBurnedSecretRecord,
  mockMetadataRecord,
  mockMetadataRecordsList,
  mockNotReceivedSecretRecord1,
  mockOrphanedMetadataRecord,
  mockOrphanedSecretRecord,
  mockReceivedMetadataRecord,
  mockReceivedSecretRecord,
  mockReceivedSecretRecord1,
  mockReceivedSecretRecord2,
  mockSecretRecord,
} from '../fixtures/metadata';

describe('Metadata Fixtures Integrity', () => {
  describe('Individual Metadata Records', () => {
    const testCases = [
      {
        name: 'Default Metadata Record',
        record: mockMetadataRecord,
        expectedState: MetadataState.NEW,
        expectedSecretKey: 'secret-test-key-123',
        expectedSecretShortkey: 'secret-abc123',
      },
      {
        name: 'Burned Metadata Record',
        record: mockBurnedMetadataRecord,
        expectedState: MetadataState.BURNED,
        expectedSecretKey: 'secret-burned-key-123',
        expectedSecretShortkey: 'secret-burned-abc123',
      },
      {
        name: 'Received Metadata Record',
        record: mockReceivedMetadataRecord,
        expectedState: MetadataState.RECEIVED,
        expectedSecretKey: 'secret-received-key-123',
        expectedSecretShortkey: 'secret-received-abc123',
      },
      {
        name: 'Orphaned Metadata Record',
        record: mockOrphanedMetadataRecord,
        expectedState: MetadataState.ORPHANED,
        expectedSecretKey: 'secret-orphaned-key-123',
        expectedSecretShortkey: 'secret-orphaned-abc123',
      },
    ];

    testCases.forEach(
      ({ name, record, expectedState, expectedSecretKey, expectedSecretShortkey }) => {
        it(`${name} has correct structure and keys`, () => {
          expect(record).toBeTruthy();
          expect(record.state).toBe(expectedState);
          expect(record.secret_key).toBe(expectedSecretKey);
          expect(record.secret_shortkey).toBe(expectedSecretShortkey);

          // Check date fields
          expect(record.created).toBeInstanceOf(Date);
          expect(record.updated).toBeInstanceOf(Date);
        });
      }
    );
  });

  describe('Metadata Records List', () => {
    it('has correct structure', () => {
      expect(mockMetadataRecordsList).toBeTruthy();
      expect(mockMetadataRecordsList.type).toBe('list');
      expect(mockMetadataRecordsList.received).toHaveLength(2);
      expect(mockMetadataRecordsList.notreceived).toHaveLength(1);
    });

    it('received records have unique and correct keys', () => {
      const receivedRecords = mockMetadataRecordsList.received;

      expect(receivedRecords[0].secret_key).toBe('secret-received-1');
      expect(receivedRecords[0].secret_shortkey).toBe('sec-rcv1');
      expect(receivedRecords[0].state).toBe(MetadataState.RECEIVED);

      expect(receivedRecords[1].secret_key).toBe('secret-received-2');
      expect(receivedRecords[1].secret_shortkey).toBe('sec-rcv2');
      expect(receivedRecords[1].state).toBe(MetadataState.RECEIVED);
    });

    it('not received record has correct keys', () => {
      const notReceivedRecord = mockMetadataRecordsList.notreceived[0];

      expect(notReceivedRecord.secret_key).toBe('secret-not-received-1');
      expect(notReceivedRecord.secret_shortkey).toBe('sec-nrcv1');
      expect(notReceivedRecord.state).toBe(MetadataState.NEW);
    });
  });

  describe('Corresponding Secret Records', () => {
    const secretRecordTestCases = [
      {
        name: 'Default Secret Record',
        secretRecord: mockSecretRecord,
        expectedKey: 'testkey123',
        expectedState: SecretState.NEW,
      },
      {
        name: 'Burned Secret Record',
        secretRecord: mockBurnedSecretRecord,
        expectedKey: 'secret-burned-key-123',
        expectedState: SecretState.BURNED,
      },
      {
        name: 'Received Secret Record',
        secretRecord: mockReceivedSecretRecord,
        expectedKey: 'secret-received-key-123',
        expectedState: SecretState.RECEIVED,
      },
      {
        name: 'Orphaned Secret Record',
        secretRecord: mockOrphanedSecretRecord,
        expectedKey: 'secret-orphaned-key-123',
        expectedState: SecretState.VIEWED,
      },
    ];

    secretRecordTestCases.forEach(
      ({ name, secretRecord, expectedKey, expectedState }) => {
        it(`${name} has correct structure`, () => {
          expect(secretRecord).toBeTruthy();
          expect(secretRecord.key).toBe(expectedKey);
          expect(secretRecord.state).toBe(expectedState);

          // Validate common fields
          expect(secretRecord.is_truncated).toBe(false);
          expect(secretRecord.has_passphrase).toBe(false);
          expect(secretRecord.verification).toBe(true);
        });
      }
    );

    it('additional list metadata secret records exist', () => {
      expect(mockReceivedSecretRecord1.key).toBe('secret-received-1');
      expect(mockReceivedSecretRecord2.key).toBe('secret-received-2');
      expect(mockNotReceivedSecretRecord1.key).toBe('secret-not-received-1');
    });
  });

  describe('1:1 Relationship Verification', () => {
    it('metadata records match their corresponding secret records', () => {
      const verificationCases = [
        {
          metadataRecord: mockMetadataRecordsList.received[0],
          secretRecord: mockReceivedSecretRecord1,
        },
        {
          metadataRecord: mockMetadataRecordsList.received[1],
          secretRecord: mockReceivedSecretRecord2,
        },
        {
          metadataRecord: mockMetadataRecordsList.notreceived[0],
          secretRecord: mockNotReceivedSecretRecord1,
        },
      ];

      verificationCases.forEach(({ metadataRecord, secretRecord }) => {
        expect(metadataRecord.secret_key).toBe(secretRecord.key);
        expect(metadataRecord.secret_shortkey).toBe(secretRecord.shortkey);
      });
    });
  });
});
