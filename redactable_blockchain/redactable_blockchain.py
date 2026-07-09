import binascii
import time
import random
import json
import ecdsa
from hashlib import sha256

from Crypto.PublicKey import RSA

from Crypto.Hash import RIPEMD160, SHA256
from Crypto.Signature import pkcs1_15

from ats import ats_key_gen, ats_sign, ats_combine, ats_verify
from merkle_tree import get_merkle_root


# Test PARAMETERS change as needed
test_run_number = 100
ats_signature_number = 100
ats_threshold = 51


def generate_ds_key_pair():
    sk = ecdsa.SigningKey.generate(curve=ecdsa.SECP256k1, hashfunc=sha256)  # The default is sha1
    vk = sk.get_verifying_key()
    return sk, vk, vk.to_string("compressed").hex()


def ds_validate(public_key, message, signature):
    vk = ecdsa.VerifyingKey.from_string(bytes.fromhex(public_key), curve=ecdsa.SECP256k1,
                                        hashfunc=sha256)
    return vk.verify(bytes.fromhex(signature), message.encode("utf-8"))


def calculate_hash(data, hash_function: str = "sha256") -> str:
    data = bytearray(data, "utf-8")
    if hash_function == "sha256":
        h = SHA256.new()
        h.update(data)
        return h.hexdigest()
    if hash_function == "ripemd160":
        h = RIPEMD160.new()
        h.update(data)
        return h.hexdigest()


# dummy 800ish bytes transaction message
message = ""
for i in range(800):
    message += str(1)

# create ats key pairs for ta
ats_pk_list, ats_sk_list, p, q, g = ats_key_gen(ats_signature_number, ats_threshold)
ats_public_key_hash = calculate_hash(calculate_hash(json.dumps(ats_pk_list), hash_function="sha256"),
                                     hash_function="ripemd160")

# create ds key pairs for user and ta
user = generate_ds_key_pair()
ta = generate_ds_key_pair()

acl = {user[2]: "user", ta[2]: "ta", ats_public_key_hash: (ats_pk_list, ats_sk_list)}  # Access Control List


class RedactableBlockchain:
    def __init__(self, ):
        self.chain = []
        self.url = {}  # Unconfirmed Redaction List

    @staticmethod
    def create_tx():
        tx = {"hash": None, "header": {"ts": None, "q": calculate_hash(json.dumps(message))}, "data": message}
        signature = user[0].sign(tx["header"]["q"].encode("utf-8")).hex()
        tx["header"]["ts"] = (user[2], signature)
        print(tx["header"])
        tx["hash"] = calculate_hash(json.dumps(tx["header"]))
        return tx

    @staticmethod
    def create_rtx(who, ri):
        rtx = {"hash": None, "header": {"ri": ri, "rs": None, "taa": None}}
        signature = who[0].sign(str(rtx["header"]["ri"]).encode("utf-8")).hex()
        rtx["header"]["rs"] = (who[2], signature)
        return rtx

    def validate_tx(self, tx):
        # try:
        if tx["header"]["ts"][0] not in acl:
            print("ERROR: sender public key not exist in url, invalid tx")
            return False
        if tx["hash"] != calculate_hash(json.dumps(tx["header"])):
            print("ERROR: hash of transaction header data not match transaction hash, invalid tx")
            return False

        if tx["header"]["q"] != calculate_hash(json.dumps(tx["data"])):
            print("data got redacted or modified")
            if len(self.chain) < tx["data"][0]:
                # block not add to chain yet, add index to url for later checking
                if tx["data"][0] not in self.url:
                    self.url[tx["data"][0]] = []
                if tx["data"][1] not in self.url[tx["data"][0]]:
                    self.url[tx["data"][0]].append(tx["data"][1])
            elif tx["data"][1] <= len(self.chain[tx["data"][0]]) - 1:
                if self.validate_rtx(self.chain[tx["data"][0]][tx["data"][1]], tx["data"][0], tx["data"][1],
                                     mtx=tx) != 2:
                    # invalid rtx
                    return False
            else:
                # rtx not found in the provided block
                return False
        if not ds_validate(tx["header"]["ts"][0], tx["header"]["q"], tx["header"]["ts"][1]):
            print("ERROR: invalid signature")
            return False

        return True
        # except Exception:
        #     return False

    def validate_rtx(self, rtx, mb_rtx, ti_rtx, add=False, mtx=None, setup=False):
        # try:
        rtx_header_without_taa = rtx["header"].copy()
        rtx_header_without_taa.pop("taa")

        if not ds_validate(rtx["header"]["rs"][0], str(rtx["header"]["ri"]), rtx["header"]["rs"][1]) or "data" in rtx or (
                rtx["header"]["taa"] and (
                rtx["hash"] != calculate_hash(json.dumps(rtx["header"])) or not
                ats_verify(ats_threshold, ats_pk_list, json.dumps(rtx_header_without_taa),
                           rtx["header"]["taa"][1][0], rtx["header"]["taa"][1][1],
                           rtx["header"]["taa"][2], p, q, g) or (add and rtx["header"]["taa"][0] not in acl))):
            print("ERROR: invalid signature or rtx contain data or "
                  "rtx is confirmed but hash is different or invalid ats or new rtx but ats is not in acl")
            return False

        for index in rtx["header"]["ri"]:
            block_tx_index = index[0]
            tx_index = index[1]
            tx = self.chain[block_tx_index]["txs"][tx_index]
            if not mtx or tx == mtx:
                if add:
                    if calculate_hash(json.dumps(tx["data"])) != tx["header"]["q"] or (
                            rtx["header"]["rs"][0] != tx["header"]["ts"][0] and acl[rtx["header"]["rs"][0]] != "ta"):
                        print("ERROR: tx already got redacted or (rtx sender is not the same as tx sender and not TA)")
                        return False
                elif calculate_hash(json.dumps(tx["data"])) == tx["header"]["q"]:
                    if not setup:
                        print("ERROR: SETUP incorrect redact data")
                        return False

        if setup:
            if not rtx["header"]["taa"]:
                return 0
            self.redact_tx(rtx, mb_rtx, ti_rtx)

        if not rtx["header"]["taa"]:
            return 1
        return 2
        # except Exception:
        #     return False

    def confirm_rtx_by_ta(self, rtx, mb_rtx, ti_rtx):
        if self.validate_rtx(rtx, mb_rtx, ti_rtx, add=True):
            random_ta_signers = sorted(tuple(random.sample(list(range(ats_signature_number))[1:] +
                                                           [ats_signature_number], int(ats_signature_number / 2) + 1)))
            rtx_header_without_taa = rtx["header"].copy()
            rtx_header_without_taa.pop("taa")
            taa = (ats_public_key_hash,
                   ats_combine(random_ta_signers,
                               ats_sign(json.dumps(rtx_header_without_taa), random_ta_signers, ats_pk_list, ats_sk_list, p, q, g)),
                   random_ta_signers)
            rtx["header"]["taa"] = taa
            rtx["hash"] = calculate_hash(json.dumps(rtx["header"]))
            return True
        return False

    def redact_tx(self, rtx, mb_rtx, ti_rtx):
        for ri in rtx["header"]["ri"]:
            self.chain[ri[0]]["txs"][ri[1]]["data"] = (mb_rtx, ti_rtx)

    def validate_block(self, block, block_index, add=False, setup=False):
        if block_index and not calculate_hash(json.dumps(self.chain[block_index - 1]["header"])) == block["header"]["prev_block_hash"]:
            print("ERROR: previous block hash mismatch")
            return False

        if block_index in self.url:  # check for unconfirmed redaction transactions that must exist in the block
            for rtx_i in self.url[block_index]:
                if rtx_i not in block["txs"]:
                    print("ERROR: unconfirmed redaction transaction not exist in intended block, block is invalid")
                    return False

        for tx in block["txs"]:
            if "rs" in tx["header"]:  # redaction transaction
                if not self.validate_rtx(tx, block_index, block["txs"].index(tx), add=add, setup=setup):
                    print("ERROR: invalid redaction transaction")
                    return False
            else:
                if not self.validate_tx(tx):
                    print("ERROR: invalid transaction")
                    return False
        return True

    def mine_block(self, txs):
        """This prototype does not include mining proof"""
        prev_block_hash = ""
        if self.chain:
            prev_block_hash = calculate_hash(json.dumps(self.chain[-1]["header"]))
        new_block = {"header": {"prev_block_hash": prev_block_hash, "merkle": get_merkle_root(txs),
                                "timestamp": time.time()},
                     "txs": txs}
        if self.validate_block(new_block, len(self.chain), add=True):
            self.chain.append(new_block)
            for tx in txs:
                if "rs" in tx["header"]:  # redaction transaction
                    self.redact_tx(tx, len(self.chain) - 1, txs.index(tx))


def display_chain(chain):
    for block_index, block in enumerate(chain.chain):
        print("block " + str(block_index) + ": ")
        print(block)


def add_block(chain):
    tx = chain.create_tx()
    chain.mine_block([tx])


def test_validation(chain):
    if len(chain.chain):
        validate_time = []
        print("running validation test on last block (block " + str(len(chain.chain) - 1) +
              ") for " + str(test_run_number) + " times")
        for _ in range(test_run_number):
            start_time = time.time()
            chain.validate_block(chain.chain[-1], len(chain.chain) - 1)
            end_time = time.time() - start_time
            validate_time.append(end_time)
        print("average validation time: " + str(sum(validate_time) / len(validate_time)))
        if "data" in chain.chain[-1]["txs"][0]:
            print("there is 1 TX in the block")
        else:
            print("there is 1 RTX in the block")
    else:
        print("ERROR: chain is empty")


def test_redaction(chain, rtx):
    if not len(chain.chain):
        print("ERROR: chain empty")
        return
    elif "data" not in chain.chain[-1]["txs"][0]:
        print("ERROR: last chain contains no tx")
    if chain.confirm_rtx_by_ta(rtx, len(chain.chain) - 1, 0):
        chain.mine_block([rtx])
        print("Transaction in this block got redacted", chain.chain[-2])
    else:
        print("Redaction Error")


def test_redaction_user(chain):
    rtx = chain.create_rtx(user, [(len(chain.chain) - 1, 0)])
    test_redaction(chain, rtx)


def test_redaction_ta(chain):
    rtx = chain.create_rtx(ta, [(len(chain.chain) - 1, 0)])
    test_redaction(chain, rtx)


def clean_blockchain(chain):
    chain.chain = []


command = {1: display_chain, 2: add_block, 3: test_validation, 4: test_redaction_user, 5: test_redaction_ta, 6: clean_blockchain}

# if __name__ == '__main__':
chain = RedactableBlockchain()
while True:
    print("Input command number:")
    print("1: Display chain")
    print("2: Add block")
    print("3: Test Validation")
    print("4: Test Redact Transaction by User on TX in the last block")
    print("5: Test Redact Transaction by TA on TX in the last block")
    print("6: Clean blockchain")
    command[int(input())](chain)
