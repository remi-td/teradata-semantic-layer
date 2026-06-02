-- Drop the shared physical TPC-H sample tables. Run this after every
-- catalog scenario that depends on this data has been uninstalled.

DROP TABLE lineitem;
DROP TABLE partsupp;
DROP TABLE orders;
DROP TABLE customer;
DROP TABLE supplier;
DROP TABLE part;
DROP TABLE nation;
DROP TABLE region;
