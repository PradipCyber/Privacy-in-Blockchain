import time
import hashlib
import random
from itertools import combinations
import sys
sys.set_int_max_str_digits(0)

import objsize


def ats_key_gen(n, t):
    sk_list = []
    pk_list = []
    pk_list.append(t)
    sk_list.append(0)
    q = 264926624393126082647786234614522411169
    p = 34970314419892642909507782969116958274309
    g = 27464808337291794528868661597410061338052
    for i in range(1, n + 1):
        sk = random.randint(1, q)
        pk = pow(g, sk, p)
        sk_list.append(sk)
        pk_list.append(pk)
    # print(pk_list, len(pk_list))
    return pk_list, sk_list, p, q, g


def ats_sign(m, C, pk_list, sk_list, p, q, g):
    signatures_list = []
    R = 1
    r_map = {}
    R_map = {}
    for item in C:
        r_item = random.randint(1, q)
        r_map[item] = r_item
        R_item = pow(g, r_item, p)
        R_map[item] = R_item
        R = R * R_item

    for item in C:
        sk = sk_list[item]
        r = r_map[item]
        R2 = R_map[item]
        hkp1 = hashlib.sha256((str(pk_list) + str(R) + m).encode()).hexdigest()
        c = int(hkp1, 16) % q
        z = (r + c * sk) % q
        bigIntegers = [R2, z]
        signatures_list.append(bigIntegers)

    return signatures_list


def ats_combine(C, signatures_list):
    Z = 0
    R = 1
    for item in signatures_list:
        r = item[0]
        z = item[1]
        R = R * r
        Z = Z + z
    return R, Z, C


def ats_verify(t, pk_list, m, R, Z, C, p, q, g):
    pk_C = 1
    for i in C:
        pk = pk_list[i]
        pk_C = pk_C * pk
    # print("pk", pk_C)
    hkp1 = hashlib.sha256((str(pk_list) + str(R) + m).encode()).hexdigest()
    c = int(hkp1, 16) % q

    if len(C) >= t and pow(g, Z, p) == (pow(pk_C, c, p) * R) % p:
        return True
    else:
        return False


if __name__ == '__main__':
    m = ""
    for i in range(800):
        m += str(1)
    print("msg size:%s bytes" % (objsize.get_deep_size(m) / 1024 * 1000))
    # 1.KeyGen()
    test = 100
    n = 50  # number of total key
    print("test ATS with n=" + str(n) + " λ=" + str(int(n / 2) + 1))

    gen_time = []
    sign_time = []
    combine_time = []
    verify_time = []
    for _ in range(test):
        C = sorted(tuple(random.sample(list(range(int(n)))[1:] + [n], int(n / 2) + 1)))  # pick 51% of n to sign
        # print(len(C), C)
        t = len(C)
        start_time = time.time()
        pk_list, sk_list, p, q, g = ats_key_gen(n, t)
        # print(pk_list)
        end_time = time.time() - start_time
        gen_time.append(end_time)
        # print("gen：%s ms" % (end_time))

        # 2.Sign()
        start_time = time.time()
        signatures_list = ats_sign(m, C, pk_list, sk_list, p, q, g)
        end_time = time.time() - start_time
        sign_time.append(end_time)
        # print("sign：%s ms" % (end_time))

        # 3.Combine
        start_time = time.time()
        signature = ats_combine(C, signatures_list)
        end_time = time.time() - start_time
        combine_time.append(end_time)
        # print("combine：%s ms" % (end_time))

        # 4.verify and trace
        start_time = time.time()
        res0 = ats_verify(t, pk_list, m, signature[0], signature[1], C, p, q, g)
        end_time = time.time() - start_time
        verify_time.append(end_time)
        # print("verify：%s ms" % (end_time))
        # print(res0)

    print("gen time", sum(gen_time) / len(gen_time))
    print("sign time", sum(sign_time) / len(sign_time))
    print("combine time", sum(combine_time) / len(combine_time))
    print("verify and trace time", sum(verify_time) / len(verify_time))

    print("sign overhead:%s bytes" % (objsize.get_deep_size(signatures_list[0]) / 1024 * len(C) * 1000))

    print("total combine overhead:%s bytes" % ((objsize.get_deep_size(signature[0]) + objsize.get_deep_size(signature[1])) / 1024 * 1000))


