// src/tests/fixtures/metadata.fixture.spec.ts
import { MetadataState } from '@/schemas/models/metadata';
import { SecretState } from '@/schemas/models/secret';
import { describe, expect, it } from 'vitest';

import {
  mockBurnedMetadataRecord,
  mockBurnedSecretRecord,
  mockMetadataRecent,
  mockMetadataRecord,
  mockNotReceivedSecretRecord1,
  mockOrphanedMetadataRecord,
  mockOrphanedSecretRecord,
  mockReceivedMetadataRecord,
  mockReceivedSecretRecord,
  mockReceivedSecretRecord1,
  mockReceivedSecretRecord2,
  mockSecretRecord,
} from '../fixtures/metadata.fixture';

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
        it(`"${name}" has correct structure and keys`, () => {
          expect(record).toBeTruthy();
          expect(record.state).toBe(expectedState);
          expect(record.secret_key).toBe(expectedSecretKey);
          expect(record.secret_shortid).toBe(expectedSecretShortkey);

          // Check date fields
          expect(record.created).toBeInstanceOf(Date);
          expect(record.updated).toBeInstanceOf(Date);
          expect(record.updated.getTime()).toBeGreaterThanOrEqual(record.created.getTime());
        });
      }
    );
  });

  describe('Negative test cases', () => {
    it('Burned metadata record is not null', () => {
      expect(mockBurnedMetadataRecord).toBeTruthy();
      expect(mockBurnedMetadataRecord.state).toBe(MetadataState.BURNED);
      expect(mockBurnedMetadataRecord.burned).toBeInstanceOf(Date);
      expect(mockBurnedMetadataRecord.secret_key).toBe('secret-burned-key-123');
      expect(mockBurnedMetadataRecord.secret_shortid).toBe('secret-burned-abc123');
    });

    it('Orphaned metadata record is not null', () => {
      expect(mockOrphanedMetadataRecord).toBeTruthy();
      expect(mockOrphanedMetadataRecord.state).toBe(MetadataState.ORPHANED);
      expect(mockOrphanedMetadataRecord.secret_key).toBe('secret-orphaned-key-123');
      expect(mockOrphanedMetadataRecord.secret_shortid).toBe('secret-orphaned-abc123');
    });
    it('rejects invalid metadata state', () => {
      // Assuming MetadataState is an enum or a union type
      const isValidState = (state: any): state is MetadataState =>
        Object.values(MetadataState).includes(state);

      expect(() => {
        const invalidRecord = {
          ...mockMetadataRecord,
          state: 'INVALID_STATE',
        };

        if (!isValidState(invalidRecord.state)) {
          throw new Error('Invalid metadata state');
        }
      }).toThrow('Invalid metadata state');
    });
  });

  describe('Metadata Records List', () => {
    it('has correct structure', () => {
      expect(mockMetadataRecent.details).toBeTruthy();
      expect(mockMetadataRecent.details.type).toBe('list');
      expect(mockMetadataRecent.details.received).toHaveLength(1);
      expect(mockMetadataRecent.details.notreceived).toHaveLength(1);
    });

    it('received records have unique and correct keys', () => {
      const receivedRecords = mockMetadataRecent.details.received;

      expect(receivedRecords[0].key).toBe('received-metadata-1');
      expect(receivedRecords[0].shortid).toBe('rcv-short-1');
      expect(receivedRecords[0].state).toBe(MetadataState.RECEIVED);
    });

    it('not received record has correct keys', () => {
      const notReceivedRecord = mockMetadataRecent.details.notreceived[0];

      expect(notReceivedRecord.key).toBe('not-received-metadata-1');
      expect(notReceivedRecord.shortid).toBe('nrcv-short-1');
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

    secretRecordTestCases.forEach(({ name, secretRecord, expectedKey, expectedState }) => {
      it(`"${name}" has correct structure`, () => {
        expect(secretRecord).toBeTruthy();
        expect(secretRecord.key).toBe(expectedKey);
        expect(secretRecord.state).toBe(expectedState);

        // Validate common fields
        expect(secretRecord.is_truncated).toBe(false);
        expect(secretRecord.has_passphrase).toBe(false);
        expect(secretRecord.verification).toBe(true);
      });
    });

    it('Burned secret record is null', () => {
      expect(mockBurnedSecretRecord).toBeNull();
    });

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
          metadataRecord: mockMetadataRecent.details.received[0],
          secretRecord: {
            key: 'sec-rcv-1',
            shortid: 'rcv-short-1',
          },
        },
        {
          metadataRecord: mockMetadataRecent.details.notreceived[0],
          secretRecord: {
            key: 'sec-nrcv-1',
            shortid: 'nrcv-short-1',
          },
        },
      ];

      verificationCases.forEach(({ metadataRecord, secretRecord }) => {
        expect(metadataRecord.secret_shortid).toBe(secretRecord.key);
        expect(metadataRecord.shortid).toBe(secretRecord.shortid);
      });
    });
  });

  describe('Metadata Records Validation', () => {
    it('validates metadata timestamps', () => {
      const records = [
        ...mockMetadataRecent.details.received,
        ...mockMetadataRecent.details.notreceived,
      ];

      records.forEach((record) => {
        expect(record.created).toBeInstanceOf(Date);
        expect(record.updated).toBeInstanceOf(Date);
        expect(record.updated.getTime()).toBeGreaterThanOrEqual(record.created.getTime());
      });
    });

    it('validates required fields are present', () => {
      const records = [
        ...mockMetadataRecent.details.received,
        ...mockMetadataRecent.details.notreceived,
      ];

      records.forEach((record) => {
        expect(record.key).toBeTruthy();
        expect(record.shortid).toBeTruthy();
        expect(record.state).toBeDefined();
        expect(record.custid).toBeTruthy();
        expect(typeof record.secret_ttl).toBe('number');
      });
    });
  });
});
