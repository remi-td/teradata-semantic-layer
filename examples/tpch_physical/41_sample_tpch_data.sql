-- =========================================================================
-- Sample TPC-H data — small synthetic load (not reference TPC-H data,
-- just enough to exercise the semantic layer's compiled SQL meaningfully).
-- =========================================================================

-- 5 regions
INSERT INTO demo_user.region VALUES (0, 'AFRICA',      'lar deposits. blithely final packages cajole. regular waters are final requests.');
INSERT INTO demo_user.region VALUES (1, 'AMERICA',     'hs use ironic, even requests. s');
INSERT INTO demo_user.region VALUES (2, 'ASIA',        'ges. thinly even pinto beans ca');
INSERT INTO demo_user.region VALUES (3, 'EUROPE',      'ly final courts cajole furiously final excuse');
INSERT INTO demo_user.region VALUES (4, 'MIDDLE EAST', 'uickly special accounts cajole carefully blithely close requests.');

-- 15 nations across 5 regions
INSERT INTO demo_user.nation VALUES (0,  'ALGERIA',       0, 'haggle. carefully final deposits detect slyly agai');
INSERT INTO demo_user.nation VALUES (1,  'ARGENTINA',     1, 'al foxes promise slyly according to the regular accounts.');
INSERT INTO demo_user.nation VALUES (2,  'BRAZIL',        1, 'y alongside of the pending deposits.');
INSERT INTO demo_user.nation VALUES (3,  'CANADA',        1, 'eas hang ironic, silent packages.');
INSERT INTO demo_user.nation VALUES (4,  'EGYPT',         4, 'y above the carefully unusual theodolites.');
INSERT INTO demo_user.nation VALUES (5,  'ETHIOPIA',      0, 'ven packages wake quickly.');
INSERT INTO demo_user.nation VALUES (6,  'FRANCE',        3, 'refully final requests. regular, ironi');
INSERT INTO demo_user.nation VALUES (7,  'GERMANY',       3, 'l platelets. regular accounts x-ray.');
INSERT INTO demo_user.nation VALUES (8,  'INDIA',         2, 'ss excuses cajole slyly across.');
INSERT INTO demo_user.nation VALUES (9,  'INDONESIA',     2, 'slyly express asymptotes.');
INSERT INTO demo_user.nation VALUES (10, 'IRAN',          4, 'efully alongside of the slyly final dependencies.');
INSERT INTO demo_user.nation VALUES (11, 'IRAQ',          4, 'nic deposits boost atop the quickly final requests.');
INSERT INTO demo_user.nation VALUES (12, 'JAPAN',         2, 'ously. final, express gifts cajole.');
INSERT INTO demo_user.nation VALUES (13, 'UNITED KINGDOM',3, 'eans boost carefully special requests.');
INSERT INTO demo_user.nation VALUES (14, 'UNITED STATES', 1, 'y final packages. slow foxes cajole quickly.');

-- 12 customers across 5 market segments
INSERT INTO demo_user.customer VALUES (1, 'Customer#000000001', 'IVhzIApeRb',        14, '25-989-741-2988',   711.56, 'BUILDING',   'to the even, regular platelets.');
INSERT INTO demo_user.customer VALUES (2, 'Customer#000000002', 'XSTf4,NCwDVaWNe6',   6, '23-768-687-3665',   121.65, 'AUTOMOBILE', 'l accounts. blithely ironic.');
INSERT INTO demo_user.customer VALUES (3, 'Customer#000000003', 'MG9kdTD2WBHm',       1, '11-719-748-3364',  7498.12, 'AUTOMOBILE', 'deposits eat slyly ironic.');
INSERT INTO demo_user.customer VALUES (4, 'Customer#000000004', 'XxVSJsLAGtn',        4, '14-128-190-5944',  2866.83, 'MACHINERY',  'y final requests wake.');
INSERT INTO demo_user.customer VALUES (5, 'Customer#000000005', 'KvpyuHCplrB84WgAi', 12, '13-750-942-6364',   794.47, 'HOUSEHOLD',  'n accounts will have to unwind.');
INSERT INTO demo_user.customer VALUES (6, 'Customer#000000006', 'sKZz0CsnMD7mp4Xd0', 14, '30-114-968-4951',  7638.57, 'AUTOMOBILE', 'tions. even deposits boost.');
INSERT INTO demo_user.customer VALUES (7, 'Customer#000000007', 'TcGe5gaZNgVePxU5', 11, '18-338-906-3675',  9561.95, 'BUILDING',   'ainst the ironic, express theodolites.');
INSERT INTO demo_user.customer VALUES (8, 'Customer#000000008', 'I0B10bB0AymmC',      8, '17-147-757-1694',  6819.74, 'BUILDING',   'among the slyly regular theodolites.');
INSERT INTO demo_user.customer VALUES (9, 'Customer#000000009', 'xKiAFTjUsCuxfele',   7, '16-158-899-1951',  8324.07, 'FURNITURE',  'r theodolites according to the.');
INSERT INTO demo_user.customer VALUES (10,'Customer#000000010', '6LrEaV6KR6PLVcgl',   2, '32-984-798-9345',  2753.54, 'HOUSEHOLD',  'es regular deposits haggle.');
INSERT INTO demo_user.customer VALUES (11,'Customer#000000011', 'PkWS 3HlXqwTuzrKg', 13, '11-710-812-4866', -272.60, 'BUILDING',   'ckages. requests sleep slyly.');
INSERT INTO demo_user.customer VALUES (12,'Customer#000000012', '9PWKuhzT4Zr1Q',      3, '13-571-949-2356', 3396.49, 'HOUSEHOLD',  'to the carefully final braids.');

-- 20 orders across 4 years and all priority levels
INSERT INTO demo_user.orders VALUES (1,  1, 'O',  173665.47, DATE '1996-01-02', '5-LOW',            'Clerk#000000951', 0, 'nstructions sleep.', 2);
INSERT INTO demo_user.orders VALUES (2,  3, 'O',   46929.18, DATE '1996-12-01', '1-URGENT',         'Clerk#000000880', 0, 'foxes.', 3);
INSERT INTO demo_user.orders VALUES (3,  3, 'F',  193846.25, DATE '1993-10-14', '5-LOW',            'Clerk#000000955', 0, 'special.', 1);
INSERT INTO demo_user.orders VALUES (4,  7, 'O',   32151.78, DATE '1995-10-11', '5-LOW',            'Clerk#000000124', 0, 'ledges.', 7);
INSERT INTO demo_user.orders VALUES (5,  1, 'F',  144659.20, DATE '1994-07-30', '5-LOW',            'Clerk#000000925', 0, 'haggle.', 1);
INSERT INTO demo_user.orders VALUES (6,  2, 'F',   58749.59, DATE '1992-02-21', '4-NOT SPECIFIED',  'Clerk#000000058', 0, 'furiously.', 2);
INSERT INTO demo_user.orders VALUES (7,  6, 'O',  252004.18, DATE '1996-01-10', '2-HIGH',           'Clerk#000000470', 0, 'carefully.', 6);
INSERT INTO demo_user.orders VALUES (8,  8, 'O',   69468.50, DATE '1995-10-21', '5-LOW',            'Clerk#000000616', 0, 'requests.', 8);
INSERT INTO demo_user.orders VALUES (9,  5, 'F',   84651.80, DATE '1993-04-14', '1-URGENT',         'Clerk#000000490', 0, 'ironic.', 5);
INSERT INTO demo_user.orders VALUES (10, 4, 'O',  147775.96, DATE '1998-03-20', '2-HIGH',           'Clerk#000000057', 0, 'luminately.', 4);
INSERT INTO demo_user.orders VALUES (11, 9, 'O',  228190.42, DATE '1997-05-04', '3-MEDIUM',         'Clerk#000000025', 0, 'even.', 9);
INSERT INTO demo_user.orders VALUES (12, 9, 'F',   93018.79, DATE '1992-11-22', '4-NOT SPECIFIED',  'Clerk#000000446', 0, 'nag.', 9);
INSERT INTO demo_user.orders VALUES (13,12, 'O',   65282.00, DATE '1998-05-16', '3-MEDIUM',         'Clerk#000000213', 0, 'ounts.', 12);
INSERT INTO demo_user.orders VALUES (14,10, 'F',   32114.39, DATE '1994-02-28', '5-LOW',            'Clerk#000000807', 0, 'idly.', 10);
INSERT INTO demo_user.orders VALUES (15, 7, 'O',   87568.10, DATE '1997-01-11', '4-NOT SPECIFIED',  'Clerk#000000355', 0, 'accounts.', 7);
INSERT INTO demo_user.orders VALUES (16, 1, 'F',  126920.00, DATE '1993-12-20', '2-HIGH',           'Clerk#000000115', 0, 'unusual.', 1);
INSERT INTO demo_user.orders VALUES (17, 6, 'O',   32863.29, DATE '1998-10-14', '3-MEDIUM',         'Clerk#000000121', 0, 'carefully.', 6);
INSERT INTO demo_user.orders VALUES (18, 2, 'F',  143411.00, DATE '1995-07-01', '1-URGENT',         'Clerk#000000334', 0, 'nstrn.', 2);
INSERT INTO demo_user.orders VALUES (19, 8, 'O',   64049.26, DATE '1996-03-10', '4-NOT SPECIFIED',  'Clerk#000000817', 0, 'boost.', 8);
INSERT INTO demo_user.orders VALUES (20, 4, 'F',  183655.47, DATE '1994-09-28', '1-URGENT',         'Clerk#000000687', 0, 'warhorses.', 4);

-- 10 suppliers
INSERT INTO demo_user.supplier VALUES (1, 'Supplier#000000001', 'N kD4on9OM Ipw3',  14, '25-989-741-2988', 5755.94, 'each slyly above.');
INSERT INTO demo_user.supplier VALUES (2, 'Supplier#000000002', '89eJ5ksX3ImxJQBvxo', 6, '23-768-687-3665', 4032.68, 'slyly bold instructions.');
INSERT INTO demo_user.supplier VALUES (3, 'Supplier#000000003', 'q1,G3Pj6OjIuUYfUo',  1, '11-719-748-3364', 4192.40, 'blithely silent requests.');
INSERT INTO demo_user.supplier VALUES (4, 'Supplier#000000004', 'Bk7ah4CK8SYQTep',    4, '14-128-190-5944', 4641.08, 'riously even requests.');
INSERT INTO demo_user.supplier VALUES (5, 'Supplier#000000005', 'Gcdm2rJRzl5qlTVzc', 12, '13-750-942-6364', -283.84, 'special carefully.');
INSERT INTO demo_user.supplier VALUES (6, 'Supplier#000000006', 'tQxuVm7s7CnK',      14, '30-114-968-4951', 1365.79, 'final accounts.');
INSERT INTO demo_user.supplier VALUES (7, 'Supplier#000000007', 'Fp7Fdxzb9jqhYpY',   11, '18-338-906-3675', 6820.35, 's cajole quickly.');
INSERT INTO demo_user.supplier VALUES (8, 'Supplier#000000008', 'naQwF5YtBrvsHLcx',   8, '17-147-757-1694', 7627.85, 'regular excuses.');
INSERT INTO demo_user.supplier VALUES (9, 'Supplier#000000009', 'm48UQr nXxEAT',      7, '16-158-899-1951', 5302.37, 'carefully special.');
INSERT INTO demo_user.supplier VALUES (10,'Supplier#000000010', 'Saygah3gYWMp72i',    2, '32-984-798-9345', 3891.91, 'theodolites.');

-- 12 parts across 3 brands and 4 types (some PROMO% for promo_revenue metric)
INSERT INTO demo_user.part VALUES (1,  'lace spring',     'Manufacturer#1', 'Brand#13', 'PROMO BURNISHED COPPER',  7, 'JUMBO PKG',  901.00, 'ly final dependencies.');
INSERT INTO demo_user.part VALUES (2,  'rose burnished',  'Manufacturer#1', 'Brand#13', 'LARGE BRUSHED BRASS',    1,  'LG CASE',    902.00, 'lar accounts ');
INSERT INTO demo_user.part VALUES (3,  'spring green',    'Manufacturer#4', 'Brand#42', 'STANDARD POLISHED BRASS',21, 'WRAP CASE',  903.00, 'egular deposits.');
INSERT INTO demo_user.part VALUES (4,  'cornflower metal','Manufacturer#3', 'Brand#34', 'SMALL PLATED BRASS',     14, 'MED DRUM',   904.00, 'p furiously.');
INSERT INTO demo_user.part VALUES (5,  'forest brown',    'Manufacturer#3', 'Brand#32', 'STANDARD POLISHED TIN',  15, 'SM PKG',     905.00, 'wake carefully.');
INSERT INTO demo_user.part VALUES (6,  'bisque cornflower','Manufacturer#2','Brand#24', 'PROMO PLATED STEEL',      4, 'MED BAG',    906.00, 'sual a');
INSERT INTO demo_user.part VALUES (7,  'moccasin green',  'Manufacturer#1', 'Brand#11', 'SMALL PLATED COPPER',    45, 'SM BAG',     907.00, 'lyly.');
INSERT INTO demo_user.part VALUES (8,  'misty lawn',      'Manufacturer#4', 'Brand#44', 'PROMO BURNISHED TIN',    41, 'LG DRUM',    908.00, 'eposi');
INSERT INTO demo_user.part VALUES (9,  'thistle rose',    'Manufacturer#4', 'Brand#43', 'SMALL BURNISHED STEEL',  12, 'WRAP CASE',  909.00, 'ironic foxes.');
INSERT INTO demo_user.part VALUES (10, 'linen pink',      'Manufacturer#5', 'Brand#54', 'LARGE BURNISHED STEEL',  44, 'LG CAN',     910.00, 'ven packages.');
INSERT INTO demo_user.part VALUES (11, 'spring maroon',   'Manufacturer#2', 'Brand#25', 'STANDARD BURNISHED NICKEL',43,'WRAP BOX', 911.00, 'eeply bold.');
INSERT INTO demo_user.part VALUES (12, 'cornflower chocolate','Manufacturer#3','Brand#33','MEDIUM ANODIZED STEEL',25,'JUMBO CASE',912.00, 'accounts against.');

-- partsupp (each part has 2 suppliers)
INSERT INTO demo_user.partsupp VALUES (1, 1, 3325, 771.64, 'careful, express accounts');
INSERT INTO demo_user.partsupp VALUES (1, 2, 8076, 993.49, 'bold packages.');
INSERT INTO demo_user.partsupp VALUES (2, 2, 3956, 337.09, 'ounts against the.');
INSERT INTO demo_user.partsupp VALUES (2, 3, 4069, 357.84, 'after the.');
INSERT INTO demo_user.partsupp VALUES (3, 3, 8895, 378.49, 'express ideas.');
INSERT INTO demo_user.partsupp VALUES (3, 4, 4022, 314.97, 'idle dependencies.');
INSERT INTO demo_user.partsupp VALUES (4, 4, 4285, 438.68, 'even, regular platelets.');
INSERT INTO demo_user.partsupp VALUES (4, 5, 8875, 918.62, 'pearls.');
INSERT INTO demo_user.partsupp VALUES (5, 5, 5915, 592.85, 'final packages.');
INSERT INTO demo_user.partsupp VALUES (5, 6, 4693, 557.29, 'ven waters.');
INSERT INTO demo_user.partsupp VALUES (6, 6, 1226, 337.89, 'slyly regular.');
INSERT INTO demo_user.partsupp VALUES (6, 7, 7017, 590.92, 'ously.');
INSERT INTO demo_user.partsupp VALUES (7, 7, 8277, 878.47, 'ithely.');
INSERT INTO demo_user.partsupp VALUES (7, 8, 4990, 457.98, 'even packages.');
INSERT INTO demo_user.partsupp VALUES (8, 8, 1447, 741.79, 'unusual ideas.');
INSERT INTO demo_user.partsupp VALUES (8, 9, 8448, 983.25, 'express courts.');
INSERT INTO demo_user.partsupp VALUES (9, 9, 4526, 500.91, 'packages.');
INSERT INTO demo_user.partsupp VALUES (9, 10, 2477, 670.79, 'regular braids.');
INSERT INTO demo_user.partsupp VALUES (10,10, 5525, 822.98, 'posits.');
INSERT INTO demo_user.partsupp VALUES (10, 1, 3035, 255.21, 'instructions.');
INSERT INTO demo_user.partsupp VALUES (11, 1, 3325, 550.00, 'slyly silent.');
INSERT INTO demo_user.partsupp VALUES (11, 2, 3200, 480.00, 'slyly final.');
INSERT INTO demo_user.partsupp VALUES (12, 3, 2800, 620.00, 'careful.');
INSERT INTO demo_user.partsupp VALUES (12, 4, 2400, 580.00, 'regular.');

-- lineitem (multiple per order, various ship modes, return flags, discounts)
INSERT INTO demo_user.lineitem VALUES (1,  1, 1, 1, 17.00,  33078.94, 0.04, 0.02, 'N', 'O', DATE '1996-03-13', DATE '1996-02-12', DATE '1996-03-22', 'DELIVER IN PERSON', 'TRUCK', 'egular courts.');
INSERT INTO demo_user.lineitem VALUES (1,  2, 2, 2, 36.00,  38306.16, 0.09, 0.06, 'N', 'O', DATE '1996-04-12', DATE '1996-02-28', DATE '1996-04-20', 'TAKE BACK RETURN',  'MAIL',  'ly final depend.');
INSERT INTO demo_user.lineitem VALUES (1,  6, 6, 3, 8.00,    7304.48, 0.10, 0.02, 'N', 'O', DATE '1996-01-29', DATE '1996-03-05', DATE '1996-01-31', 'TAKE BACK RETURN',  'REG AIR','riously.');
INSERT INTO demo_user.lineitem VALUES (2,  3, 3, 1, 38.00,  34314.14, 0.00, 0.05, 'N', 'O', DATE '1997-01-28', DATE '1997-01-14', DATE '1997-02-02', 'TAKE BACK RETURN',  'RAIL',  'ven requests.');
INSERT INTO demo_user.lineitem VALUES (3,  4, 4, 1, 45.00,  40675.80, 0.06, 0.00, 'R', 'F', DATE '1994-02-02', DATE '1993-11-09', DATE '1994-02-23', 'NONE',              'AIR',   'ongside of the.');
INSERT INTO demo_user.lineitem VALUES (3,  8, 8, 2, 49.00,  44487.92, 0.10, 0.00, 'R', 'F', DATE '1993-11-09', DATE '1993-12-20', DATE '1993-11-24', 'TAKE BACK RETURN',  'RAIL',  'lites. fluffily.');
INSERT INTO demo_user.lineitem VALUES (3,  9, 9, 3, 27.00,  24543.03, 0.06, 0.07, 'A', 'F', DATE '1994-01-16', DATE '1993-11-22', DATE '1994-01-23', 'DELIVER IN PERSON', 'SHIP',  'deposits wake.');
INSERT INTO demo_user.lineitem VALUES (4,  1, 1, 1, 30.00,  27900.00, 0.03, 0.08, 'N', 'O', DATE '1996-01-10', DATE '1995-12-14', DATE '1996-01-18', 'DELIVER IN PERSON', 'REG AIR','sts use sly.');
INSERT INTO demo_user.lineitem VALUES (5,  6, 6, 1, 15.00,  13740.00, 0.02, 0.04, 'R', 'F', DATE '1994-10-31', DATE '1994-08-31', DATE '1994-11-20', 'NONE',              'AIR',   'riously.');
INSERT INTO demo_user.lineitem VALUES (5,  8, 8, 2, 26.00,  23608.00, 0.07, 0.08, 'R', 'F', DATE '1994-10-16', DATE '1994-09-25', DATE '1994-10-19', 'NONE',              'FOB',   'final deposits.');
INSERT INTO demo_user.lineitem VALUES (6,  3, 3, 1, 37.00,  33411.00, 0.08, 0.03, 'A', 'F', DATE '1992-04-27', DATE '1992-05-15', DATE '1992-05-02', 'TAKE BACK RETURN',  'TRUCK', 'p furiously.');
INSERT INTO demo_user.lineitem VALUES (7,  7, 7, 1, 22.00,  19954.00, 0.03, 0.08, 'N', 'O', DATE '1996-05-07', DATE '1996-03-13', DATE '1996-06-03', 'COLLECT COD',       'FOB',   'ourts cajole.');
INSERT INTO demo_user.lineitem VALUES (7,  8, 8, 2, 50.00,  45400.00, 0.02, 0.01, 'N', 'O', DATE '1996-02-01', DATE '1996-03-02', DATE '1996-02-19', 'NONE',              'TRUCK', 'regular.');
INSERT INTO demo_user.lineitem VALUES (7, 10,10, 3, 40.00,  36400.00, 0.03, 0.02, 'N', 'O', DATE '1996-01-15', DATE '1996-03-27', DATE '1996-02-03', 'TAKE BACK RETURN',  'FOB',   'boldly.');
INSERT INTO demo_user.lineitem VALUES (8,  4, 4, 1, 16.00,  14464.00, 0.10, 0.02, 'N', 'O', DATE '1995-12-04', DATE '1995-12-13', DATE '1995-12-31', 'NONE',              'MAIL',  'ts. even.');
INSERT INTO demo_user.lineitem VALUES (9,  6, 6, 1, 20.00,  18320.00, 0.06, 0.07, 'R', 'F', DATE '1993-06-25', DATE '1993-07-14', DATE '1993-07-05', 'TAKE BACK RETURN',  'REG AIR','sly carefully.');
INSERT INTO demo_user.lineitem VALUES (10, 1, 1, 1, 28.00,  26040.00, 0.00, 0.06, 'N', 'O', DATE '1998-05-14', DATE '1998-03-22', DATE '1998-06-04', 'NONE',              'SHIP',  'regular requests.');
INSERT INTO demo_user.lineitem VALUES (10, 5, 5, 2, 32.00,  28960.00, 0.09, 0.06, 'N', 'O', DATE '1998-04-01', DATE '1998-03-29', DATE '1998-04-12', 'NONE',              'TRUCK', 'ly pending.');
INSERT INTO demo_user.lineitem VALUES (11, 7, 7, 1, 30.00,  27210.00, 0.06, 0.04, 'N', 'O', DATE '1997-06-16', DATE '1997-07-01', DATE '1997-06-30', 'DELIVER IN PERSON', 'AIR',   'quickly.');
INSERT INTO demo_user.lineitem VALUES (11, 9, 9, 2, 40.00,  36360.00, 0.04, 0.06, 'N', 'O', DATE '1997-05-21', DATE '1997-07-05', DATE '1997-06-12', 'NONE',              'RAIL',  'unusual.');
INSERT INTO demo_user.lineitem VALUES (11,11, 1, 3, 25.00,  22775.00, 0.05, 0.03, 'N', 'O', DATE '1997-06-03', DATE '1997-06-20', DATE '1997-06-15', 'NONE',              'TRUCK', 'theodolites.');
INSERT INTO demo_user.lineitem VALUES (12, 2, 2, 1, 27.00,  24354.00, 0.02, 0.04, 'R', 'F', DATE '1992-12-08', DATE '1993-01-01', DATE '1993-01-02', 'COLLECT COD',       'MAIL',  'ly.');
INSERT INTO demo_user.lineitem VALUES (13, 8, 8, 1, 19.00,  17252.00, 0.00, 0.02, 'N', 'O', DATE '1998-06-17', DATE '1998-05-05', DATE '1998-06-22', 'TAKE BACK RETURN',  'AIR',   'bold.');
INSERT INTO demo_user.lineitem VALUES (14, 9, 9, 1, 12.00,  10908.00, 0.04, 0.06, 'R', 'F', DATE '1994-03-16', DATE '1994-04-19', DATE '1994-03-25', 'NONE',              'TRUCK', 'final.');
INSERT INTO demo_user.lineitem VALUES (15, 6, 6, 1, 22.00,  20152.00, 0.00, 0.08, 'N', 'O', DATE '1997-02-05', DATE '1997-01-25', DATE '1997-02-22', 'COLLECT COD',       'RAIL',  'carefully.');
INSERT INTO demo_user.lineitem VALUES (15, 7, 7, 2, 35.00,  31745.00, 0.02, 0.00, 'N', 'O', DATE '1997-03-02', DATE '1997-02-15', DATE '1997-03-21', 'DELIVER IN PERSON', 'TRUCK', 'iously.');
INSERT INTO demo_user.lineitem VALUES (16, 1, 1, 1, 22.00,  20460.00, 0.07, 0.04, 'R', 'F', DATE '1994-02-09', DATE '1994-03-11', DATE '1994-02-26', 'COLLECT COD',       'MAIL',  'carefully.');
INSERT INTO demo_user.lineitem VALUES (16, 2, 2, 2, 30.00,  27060.00, 0.06, 0.07, 'R', 'F', DATE '1994-01-17', DATE '1994-03-27', DATE '1994-02-05', 'NONE',              'RAIL',  'final theodolites.');
INSERT INTO demo_user.lineitem VALUES (17, 9, 9, 1, 14.00,  12726.00, 0.02, 0.08, 'N', 'O', DATE '1998-12-24', DATE '1998-12-18', DATE '1999-01-08', 'DELIVER IN PERSON', 'AIR',   'alongside of.');
INSERT INTO demo_user.lineitem VALUES (18, 3, 3, 1, 45.00,  40635.00, 0.04, 0.03, 'R', 'F', DATE '1995-08-23', DATE '1995-08-13', DATE '1995-09-02', 'NONE',              'TRUCK', 'egular accounts.');
INSERT INTO demo_user.lineitem VALUES (18, 8, 8, 2, 50.00,  45400.00, 0.04, 0.06, 'R', 'F', DATE '1995-07-28', DATE '1995-09-05', DATE '1995-08-17', 'NONE',              'SHIP',  'furiously final.');
INSERT INTO demo_user.lineitem VALUES (19, 4, 4, 1, 18.00,  16272.00, 0.08, 0.03, 'N', 'O', DATE '1996-05-30', DATE '1996-05-23', DATE '1996-06-09', 'TAKE BACK RETURN',  'MAIL',  'sly special.');
INSERT INTO demo_user.lineitem VALUES (20, 5, 5, 1, 49.00,  44345.00, 0.09, 0.03, 'R', 'F', DATE '1994-10-23', DATE '1994-12-04', DATE '1994-11-19', 'TAKE BACK RETURN',  'SHIP',  'carefully.');
INSERT INTO demo_user.lineitem VALUES (20, 6, 6, 2, 30.00,  27480.00, 0.00, 0.05, 'R', 'F', DATE '1994-11-19', DATE '1994-12-14', DATE '1994-12-04', 'NONE',              'REG AIR','nic foxes.');