-- =========================================================================
-- Sample TPC-H physical tables (small synthetic dataset) in demo_user.
--
-- The semantic catalog points at 'tpch.<table>', but that database is empty
-- on this sandbox. We create the same tables inside demo_user and then
-- retarget DATASET.DataBaseName so compiled SQL actually runs.
-- =========================================================================

CREATE MULTISET TABLE demo_user.region, FALLBACK (
    r_regionkey  INTEGER NOT NULL,
    r_name       VARCHAR(25) CHARACTER SET LATIN NOT CASESPECIFIC,
    r_comment    VARCHAR(152) CHARACTER SET LATIN NOT CASESPECIFIC
) UNIQUE PRIMARY INDEX (r_regionkey);

CREATE MULTISET TABLE demo_user.nation, FALLBACK (
    n_nationkey  INTEGER NOT NULL,
    n_name       VARCHAR(25) CHARACTER SET LATIN NOT CASESPECIFIC,
    n_regionkey  INTEGER,
    n_comment    VARCHAR(152) CHARACTER SET LATIN NOT CASESPECIFIC
) UNIQUE PRIMARY INDEX (n_nationkey);

CREATE MULTISET TABLE demo_user.customer, FALLBACK (
    c_custkey     INTEGER NOT NULL,
    c_name        VARCHAR(25) CHARACTER SET LATIN NOT CASESPECIFIC,
    c_address     VARCHAR(40) CHARACTER SET LATIN NOT CASESPECIFIC,
    c_nationkey   INTEGER,
    c_phone       VARCHAR(15) CHARACTER SET LATIN NOT CASESPECIFIC,
    c_acctbal     DECIMAL(12,2),
    c_mktsegment  VARCHAR(10) CHARACTER SET LATIN NOT CASESPECIFIC,
    c_comment     VARCHAR(117) CHARACTER SET LATIN NOT CASESPECIFIC
) UNIQUE PRIMARY INDEX (c_custkey);

CREATE MULTISET TABLE demo_user.orders, FALLBACK (
    o_orderkey         INTEGER NOT NULL,
    o_custkey          INTEGER,
    o_orderstatus      CHAR(1) CHARACTER SET LATIN NOT CASESPECIFIC,
    o_totalprice       DECIMAL(12,2),
    o_orderdate        DATE,
    o_orderpriority    VARCHAR(15) CHARACTER SET LATIN NOT CASESPECIFIC,
    o_clerk            VARCHAR(15) CHARACTER SET LATIN NOT CASESPECIFIC,
    o_shippriority     INTEGER,
    o_comment          VARCHAR(79) CHARACTER SET LATIN NOT CASESPECIFIC,
    -- Separate billed-to customer FK: demonstrates role-playing in the
    -- tpch_orders scenario (orders → customer has two roles).
    o_billing_custkey  INTEGER
) UNIQUE PRIMARY INDEX (o_orderkey);

CREATE MULTISET TABLE demo_user.lineitem, FALLBACK (
    l_orderkey       INTEGER NOT NULL,
    l_partkey        INTEGER,
    l_suppkey        INTEGER,
    l_linenumber     INTEGER NOT NULL,
    l_quantity       DECIMAL(12,2),
    l_extendedprice  DECIMAL(12,2),
    l_discount       DECIMAL(12,2),
    l_tax            DECIMAL(12,2),
    l_returnflag     CHAR(1) CHARACTER SET LATIN NOT CASESPECIFIC,
    l_linestatus     CHAR(1) CHARACTER SET LATIN NOT CASESPECIFIC,
    l_shipdate       DATE,
    l_commitdate     DATE,
    l_receiptdate    DATE,
    l_shipinstruct   VARCHAR(25) CHARACTER SET LATIN NOT CASESPECIFIC,
    l_shipmode       VARCHAR(10) CHARACTER SET LATIN NOT CASESPECIFIC,
    l_comment        VARCHAR(44) CHARACTER SET LATIN NOT CASESPECIFIC
) UNIQUE PRIMARY INDEX (l_orderkey, l_linenumber);

CREATE MULTISET TABLE demo_user.part, FALLBACK (
    p_partkey      INTEGER NOT NULL,
    p_name         VARCHAR(55) CHARACTER SET LATIN NOT CASESPECIFIC,
    p_mfgr         VARCHAR(25) CHARACTER SET LATIN NOT CASESPECIFIC,
    p_brand        VARCHAR(10) CHARACTER SET LATIN NOT CASESPECIFIC,
    p_type         VARCHAR(25) CHARACTER SET LATIN NOT CASESPECIFIC,
    p_size         INTEGER,
    p_container    VARCHAR(10) CHARACTER SET LATIN NOT CASESPECIFIC,
    p_retailprice  DECIMAL(12,2),
    p_comment      VARCHAR(23) CHARACTER SET LATIN NOT CASESPECIFIC
) UNIQUE PRIMARY INDEX (p_partkey);

CREATE MULTISET TABLE demo_user.supplier, FALLBACK (
    s_suppkey    INTEGER NOT NULL,
    s_name       VARCHAR(25) CHARACTER SET LATIN NOT CASESPECIFIC,
    s_address    VARCHAR(40) CHARACTER SET LATIN NOT CASESPECIFIC,
    s_nationkey  INTEGER,
    s_phone      VARCHAR(15) CHARACTER SET LATIN NOT CASESPECIFIC,
    s_acctbal    DECIMAL(12,2),
    s_comment    VARCHAR(101) CHARACTER SET LATIN NOT CASESPECIFIC
) UNIQUE PRIMARY INDEX (s_suppkey);

CREATE MULTISET TABLE demo_user.partsupp, FALLBACK (
    ps_partkey    INTEGER NOT NULL,
    ps_suppkey    INTEGER NOT NULL,
    ps_availqty   INTEGER,
    ps_supplycost DECIMAL(12,2),
    ps_comment    VARCHAR(199) CHARACTER SET LATIN NOT CASESPECIFIC
) UNIQUE PRIMARY INDEX (ps_partkey, ps_suppkey);
