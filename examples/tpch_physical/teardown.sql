-- Drop the shared physical TPC-H sample tables. Run this after every
-- catalog scenario that depends on this data has been uninstalled.

DROP TABLE demo_user.lineitem;
DROP TABLE demo_user.partsupp;
DROP TABLE demo_user.orders;
DROP TABLE demo_user.customer;
DROP TABLE demo_user.supplier;
DROP TABLE demo_user.part;
DROP TABLE demo_user.nation;
DROP TABLE demo_user.region;
