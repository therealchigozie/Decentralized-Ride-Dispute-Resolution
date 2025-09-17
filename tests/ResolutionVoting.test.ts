import { describe, it, expect, beforeEach } from "vitest";
import { cvToValue, stringUtf8CV, uintCV, principalCV, bufferCV, listCV, tupleCV } from "@stacks/transactions";

// Constants for contract interaction
const ERR_NOT_AUTHORIZED = 100;
const ERR_VOTING_CLOSED = 101;
const ERR_ALREADY_VOTED = 103;
const ERR_NOT_ARBITRATOR = 104;
const ERR_VOTING_NOT_STARTED = 105;
const ERR_INVALID_VOTE = 106;
const ERR_DISPUTE_RESOLVED = 107;
const ERR_INSUFFICIENT_ARBITRATORS = 108;
const ERR_INVALID_STAKE = 109;
const ERR_DISPUTE_NOT_FOUND = 113;
const ERR_INVALID_FEE = 128;
const ERR_ARBITRATOR_ALREADY_REGISTERED = 123;
const VOTE_DRIVER = 1;
const VOTE_PASSENGER = 2;
const VOTE_TIE = 3;
const MIN_ARBITRATORS = 3;
const MAX_ARBITRATORS = 7;
const VOTING_PERIOD = 2880;
const MIN_VOTES = 3;
const MIN_STAKE = 1000;
const REPUTATION_THRESHOLD = 50;

// Mock contract state
interface Dispute {
  id: number;
  driver: string;
  passenger: string;
  evidenceHash: Buffer;
  fee: number;
  votes: Map<string, number>;
  resolved: boolean;
  outcome?: number;
}

class ResolutionVotingMock {
  state: {
    nextDisputeId: number;
    arbitrators: Map<string, { stake: number; reputation: number }>;
    disputes: Map<number, Dispute>;
  };

  constructor() {
    this.state = {
      nextDisputeId: 1,
      arbitrators: new Map(),
      disputes: new Map(),
    };
  }

  registerArbitrator(caller: string, stake: number, reputation: number) {
    if (this.state.arbitrators.has(caller)) {
      return { value: uintCV(ERR_ARBITRATOR_ALREADY_REGISTERED) };
    }
    if (stake < MIN_STAKE) {
      return { value: uintCV(ERR_INVALID_STAKE) };
    }
    if (reputation < REPUTATION_THRESHOLD) {
      return { value: uintCV(125) }; // ERR_INVALID_REPUTATION
    }
    this.state.arbitrators.set(caller, { stake, reputation });
    return { value: { type: "boolean", value: true } };
  }

  createDispute(caller: string, driver: string, passenger: string, evidenceHash: Buffer, fee: number) {
    if (fee <= 0) {
      return { value: uintCV(ERR_INVALID_FEE) };
    }
    const disputeId = this.state.nextDisputeId++;
    this.state.disputes.set(disputeId, {
      id: disputeId,
      driver,
      passenger,
      evidenceHash,
      fee,
      votes: new Map(),
      resolved: false,
    });
    return { value: uintCV(disputeId) };
  }

  voteOnDispute(caller: string, disputeId: number, vote: number) {
    if (!this.state.arbitrators.has(caller)) {
      return { value: uintCV(ERR_NOT_ARBITRATOR) };
    }
    const dispute = this.state.disputes.get(disputeId);
    if (!dispute) {
      return { value: uintCV(ERR_DISPUTE_NOT_FOUND) };
    }
    if (dispute.resolved) {
      return { value: uintCV(ERR_DISPUTE_RESOLVED) };
    }
    if (dispute.votes.has(caller)) {
      return { value: uintCV(ERR_ALREADY_VOTED) };
    }
    if (vote !== VOTE_DRIVER && vote !== VOTE_PASSENGER && vote !== VOTE_TIE) {
      return { value: uintCV(ERR_INVALID_VOTE) };
    }
    dispute.votes.set(caller, vote);
    return { value: { type: "boolean", value: true } };
  }

  resolveDispute(disputeId: number) {
    const dispute = this.state.disputes.get(disputeId);
    if (!dispute) {
      return { value: uintCV(ERR_DISPUTE_NOT_FOUND) };
    }
    if (dispute.votes.size < MIN_VOTES) {
      return { value: uintCV(ERR_INSUFFICIENT_ARBITRATORS) };
    }
    dispute.resolved = true;
    const voteCounts = new Map<number, number>();
    dispute.votes.forEach((vote) => {
      voteCounts.set(vote, (voteCounts.get(vote) || 0) + 1);
    });
    let outcome = VOTE_TIE;
    if ((voteCounts.get(VOTE_DRIVER) || 0) > (voteCounts.get(VOTE_PASSENGER) || 0)) {
      outcome = VOTE_DRIVER;
    } else if ((voteCounts.get(VOTE_PASSENGER) || 0) > (voteCounts.get(VOTE_DRIVER) || 0)) {
      outcome = VOTE_PASSENGER;
    }
    dispute.outcome = outcome;
    return { value: uintCV(outcome) };
  }
}

describe("Resolution Voting Contract", () => {
  let contract: ResolutionVotingMock;
  const deployer = "ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM";
  const arbitrator1 = "ST1SJ3DTE5DN7X54YDH5D64R3BCB6A2AG2ZQ8YPD5";
  const arbitrator2 = "ST2CY5V39NHDPWSXMWZJD9P0T9G87S5J5V5BV5P5";
  const arbitrator3 = "ST2NEB84ASENDXKYGJPQW86YXQ8F01ZFAM8Z1J426";
  const driver = "ST3J2GVMMM2R07ZFBJDWTYEYAR8FZH5WKDTFJ9AHA";
  const passenger = "ST3NBRSFKX28FQ2ZJ1MAKX58HKHSDXNSY4Y4G77V";

  beforeEach(() => {
    contract = new ResolutionVotingMock();
  });

  describe("Arbitrator Registration", () => {
    it("should allow arbitrator registration with sufficient stake", () => {
      const result = contract.registerArbitrator(arbitrator1, MIN_STAKE, REPUTATION_THRESHOLD);
      expect(result.value.type).toBe("boolean");
      expect(result.value.value).toBe(true);
    });

    it("should fail to register with insufficient stake", () => {
      const result = contract.registerArbitrator(arbitrator1, MIN_STAKE - 1, REPUTATION_THRESHOLD);
      expect(Number(cvToValue(result.value))).toBe(ERR_INVALID_STAKE);
    });

    it("should fail to register already registered arbitrator", () => {
      contract.registerArbitrator(arbitrator1, MIN_STAKE, REPUTATION_THRESHOLD);
      const result = contract.registerArbitrator(arbitrator1, MIN_STAKE, REPUTATION_THRESHOLD);
      expect(Number(cvToValue(result.value))).toBe(ERR_ARBITRATOR_ALREADY_REGISTERED);
    });
  });

  describe("Dispute Creation", () => {
    it("should create a dispute successfully", () => {
      const evidenceHash = Buffer.from("test-evidence");
      const result = contract.createDispute(passenger, driver, passenger, evidenceHash, 1000);
      expect(Number(cvToValue(result.value))).toBe(1);
    });

    it("should fail to create dispute with invalid fee", () => {
      const evidenceHash = Buffer.from("test-evidence");
      const result = contract.createDispute(passenger, driver, passenger, evidenceHash, 0);
      expect(Number(cvToValue(result.value))).toBe(ERR_INVALID_FEE);
    });
  });

  describe("Voting on Disputes", () => {
    beforeEach(() => {
      contract.registerArbitrator(arbitrator1, MIN_STAKE, REPUTATION_THRESHOLD);
      contract.registerArbitrator(arbitrator2, MIN_STAKE, REPUTATION_THRESHOLD);
      contract.registerArbitrator(arbitrator3, MIN_STAKE, REPUTATION_THRESHOLD);
      contract.createDispute(passenger, driver, passenger, Buffer.from("test-evidence"), 1000);
    });

    it("should allow arbitrators to vote", () => {
      const result = contract.voteOnDispute(arbitrator1, 1, VOTE_DRIVER);
      expect(result.value.type).toBe("boolean");
      expect(result.value.value).toBe(true);
    });

    it("should fail if non-arbitrator votes", () => {
      const result = contract.voteOnDispute(deployer, 1, VOTE_DRIVER);
      expect(Number(cvToValue(result.value))).toBe(ERR_NOT_ARBITRATOR);
    });

    it("should fail if arbitrator votes twice", () => {
      contract.voteOnDispute(arbitrator1, 1, VOTE_DRIVER);
      const result = contract.voteOnDispute(arbitrator1, 1, VOTE_DRIVER);
      expect(Number(cvToValue(result.value))).toBe(ERR_ALREADY_VOTED);
    });

    it("should fail for invalid vote value", () => {
      const result = contract.voteOnDispute(arbitrator1, 1, 999);
      expect(Number(cvToValue(result.value))).toBe(ERR_INVALID_VOTE);
    });
  });

  describe("Dispute Resolution", () => {
    beforeEach(() => {
      contract.registerArbitrator(arbitrator1, MIN_STAKE, REPUTATION_THRESHOLD);
      contract.registerArbitrator(arbitrator2, MIN_STAKE, REPUTATION_THRESHOLD);
      contract.registerArbitrator(arbitrator3, MIN_STAKE, REPUTATION_THRESHOLD);
      contract.createDispute(passenger, driver, passenger, Buffer.from("test-evidence"), 1000);
    });

    it("should resolve dispute with majority driver votes", () => {
      contract.voteOnDispute(arbitrator1, 1, VOTE_DRIVER);
      contract.voteOnDispute(arbitrator2, 1, VOTE_DRIVER);
      contract.voteOnDispute(arbitrator3, 1, VOTE_PASSENGER);
      const result = contract.resolveDispute(1);
      expect(Number(cvToValue(result.value))).toBe(VOTE_DRIVER);
    });

    it("should fail to resolve with insufficient votes", () => {
      contract.voteOnDispute(arbitrator1, 1, VOTE_DRIVER);
      const result = contract.resolveDispute(1);
      expect(Number(cvToValue(result.value))).toBe(ERR_INSUFFICIENT_ARBITRATORS);
    });

    it("should fail to resolve non-existent dispute", () => {
      const result = contract.resolveDispute(999);
      expect(Number(cvToValue(result.value))).toBe(ERR_DISPUTE_NOT_FOUND);
    });
  });
});