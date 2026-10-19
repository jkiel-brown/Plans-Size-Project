/* ---- Open the saved dataset ---- */
libname outlib "P:\cahpr\jkiel1\Plans Project\Output";

data merged_county_final;
    set outlib.merged_county_final;
run;

/* ================================================================
   HYPERCOAGULABILITY TESTING LOW-VALUE CARE MEASURE
   ================================================================ */

/* ================= Step 1: flag acute, chronic, and test codes per claim, 2022 ================= */
data merged_county_final;
    set merged_county_final;

    array proc{5} $ hbrchcp1-hbrchcp5;
    array diag{5} $ hbdiag1-hbdiag5;

    acute_dvtpe_dx = 0;
    chronic_thrombosis_dx = 0;
    hypercoag_test_code = 0;

    do i = 1 to 5;
        if substr(diag{i},1,3) = "I26" then acute_dvtpe_dx = 1;
        if substr(diag{i},1,4) in ("I800","I801","I802","I803","I824") then acute_dvtpe_dx = 1;

        if substr(diag{i},1,4) = "I825" then chronic_thrombosis_dx = 1;
        if substr(diag{i},1,6) = "Z86711" then chronic_thrombosis_dx = 1;
        else if substr(diag{i},1,5) = "Z8671" then chronic_thrombosis_dx = 1;

        if proc{i} in ("83090","85300","85302","85303","85305","85306","85613",
                       "86146","86147","85384","85420","85730","85307","81240",
                       "81241","85240","81291","85598","85610","85670")
            then hypercoag_test_code = 1;
    end;

    drop i;
run;

/* ================= Step 2: raw flag -- test within 30 days FOLLOWING an acute dx claim ================= */
proc sql;
    create table test_claims as
    select bene_id_18900, hbclmid, hbfrom as test_date format=date9.
    from merged_county_final
    where hypercoag_test_code = 1;
quit;

proc sql;
    create table acute_dx_claims as
    select bene_id_18900, hbfrom as dx_date format=date9.
    from merged_county_final
    where acute_dvtpe_dx = 1;
quit;

proc sql;
    create table test_raw_flag as
    select distinct a.bene_id_18900, a.hbclmid, a.test_date, 1 as hypercoag_raw
    from test_claims as a
    inner join acute_dx_claims as b
      on a.bene_id_18900 = b.bene_id_18900
    where a.test_date >= b.dx_date and a.test_date <= (b.dx_date + 30);
quit;

/* ---- attach raw flag back onto merged_county_final ---- */
proc sql;
    create table merged_county_final as
    select a.*, coalesce(b.hypercoag_raw, 0) as hypercoag_raw
    from merged_county_final as a
    left join test_raw_flag as b
    on a.bene_id_18900 = b.bene_id_18900 and a.hbclmid = b.hbclmid;
quit;

/* ================= Step 3: latest raw=1 test date per beneficiary, and reference dates ================= */
proc sql;
    create table bene_latest_test as
    select bene_id_18900, max(test_date) as latest_claim_date format=date9.
    from test_raw_flag
    group by bene_id_18900;
quit;

data bene_latest_test;
    set bene_latest_test;
    ref_90  = latest_claim_date - 90;
    ref_365 = latest_claim_date - 365;
    format ref_90 ref_365 date9.;
run;

/* ================= Step 4: 2022 acute recurrence check -- window [Jan1 2022, ref_90], only if ref_90 >= Jan1 2022 ================= */
proc sql;
    create table bene_2022_acute_check as
    select a.bene_id_18900, b.ref_90, b.latest_claim_date
    from merged_county_final as a
    inner join bene_latest_test as b
      on a.bene_id_18900 = b.bene_id_18900
    where a.acute_dvtpe_dx = 1
      and b.ref_90 >= '01JAN2022'd
      and a.hbfrom <= b.ref_90;
quit;

proc sql;
    create table bene_2022_acute_exclusion as
    select distinct bene_id_18900 from bene_2022_acute_check;
quit;

/* ================= Step 5: 2022 chronic check -- window [Jan1 2022, latest_claim_date) ================= */
proc sql;
    create table bene_2022_chronic_check as
    select a.bene_id_18900
    from merged_county_final as a
    inner join bene_latest_test as b
      on a.bene_id_18900 = b.bene_id_18900
    where a.chronic_thrombosis_dx = 1
      and a.hbfrom < b.latest_claim_date;
quit;

proc sql;
    create table bene_2022_chronic_exclusion as
    select distinct bene_id_18900 from bene_2022_chronic_check;
quit;

proc sql;
    create table bene_2022_exclusion as
    select distinct bene_id_18900 from bene_2022_acute_exclusion
    outer union corr
    select distinct bene_id_18900 from bene_2022_chronic_exclusion;
quit;

/* ================= Step 6: beneficiaries still NOT excluded after 2022 checks, carrying ref dates ================= */
proc sql;
    create table bene_still_hypercoag as
    select a.bene_id_18900, a.latest_claim_date, a.ref_90, a.ref_365
    from bene_latest_test as a
    left join bene_2022_exclusion as b
    on a.bene_id_18900 = b.bene_id_18900
    where b.bene_id_18900 is null;
quit;

/* ================= Step 7: pull 2021 diagnosis claims for these beneficiaries ================= */
data claims_2021_hypercoag;
    if _n_ = 0 then set bene_still_hypercoag (keep=bene_id_18900 latest_claim_date ref_90 ref_365);

    if _n_ = 1 then do;
        declare hash hb(dataset:"bene_still_hypercoag(keep=bene_id_18900 latest_claim_date ref_90 ref_365)");
        hb.defineKey("bene_id_18900");
        hb.defineData("latest_claim_date","ref_90","ref_365");
        hb.defineDone();
    end;

    set claims.Hballenc_updated_2021 (keep=bene_id_18900 hbfrom hbdiag0-hbdiag4);

    rc = hb.find();
    if rc ne 0 then delete;
run;

data claims_2021_hypercoag_flagged;
    set claims_2021_hypercoag;

    array diag21{5} $ hbdiag0-hbdiag4;

    acute_dx21 = 0;
    chronic_dx21 = 0;

    do i = 1 to 5;
        if substr(diag21{i},1,3) = "I26" then acute_dx21 = 1;
        if substr(diag21{i},1,4) in ("I800","I801","I802","I803","I824") then acute_dx21 = 1;

        if substr(diag21{i},1,4) = "I825" then chronic_dx21 = 1;
        if substr(diag21{i},1,6) = "Z86711" then chronic_dx21 = 1;
        else if substr(diag21{i},1,5) = "Z8671" then chronic_dx21 = 1;
    end;

    drop i;
run;

/* ================= Step 8: 2021 acute recurrence check -- only if ref_90 falls in 2021 ================= */
proc sql;
    create table bene_2021_acute_exclusion as
    select distinct bene_id_18900
    from claims_2021_hypercoag_flagged
    where acute_dx21 = 1
      and ref_90 < '01JAN2022'd
      and hbfrom >= ref_365
      and hbfrom <= ref_90;
quit;

/* ================= Step 9: 2021 chronic check -- window [ref_365, end of 2021] ================= */
proc sql;
    create table bene_2021_chronic_exclusion as
    select distinct bene_id_18900
    from claims_2021_hypercoag_flagged
    where chronic_dx21 = 1
      and hbfrom >= ref_365;
quit;

proc sql;
    create table bene_2021_exclusion as
    select distinct bene_id_18900 from bene_2021_acute_exclusion
    outer union corr
    select distinct bene_id_18900 from bene_2021_chronic_exclusion;
quit;

/* ================= Step 10: combine ALL exclusions (2022 + 2021) ================= */
proc sql;
    create table bene_hypercoag_exclusion_all as
    select distinct bene_id_18900 from bene_2022_exclusion
    outer union corr
    select distinct bene_id_18900 from bene_2021_exclusion;
quit;

proc sort data=bene_hypercoag_exclusion_all nodupkey;
    by bene_id_18900;
run;

/* ================= Step 11: final flag -- zero out ALL raw=1 tests for excluded beneficiaries ================= */
proc sql;
    create table merged_county_final as
    select a.*, 
           case when b.bene_id_18900 is not null then 1 else 0 end as hypercoag_exclusion
    from merged_county_final as a
    left join bene_hypercoag_exclusion_all as b
    on a.bene_id_18900 = b.bene_id_18900;
quit;

data merged_county_final;
    set merged_county_final;
    if hypercoag_raw = 1 and hypercoag_exclusion = 0 
        then hypercoag_lvc = 1;
    else hypercoag_lvc = 0;
run;

/* ================= Beneficiary-level: anyone with at least one LVC hypercoagulability test ================= */
proc sql;
    create table bene_lowvalue_hypercoag as
    select bene_id_18900, max(hypercoag_lvc) as bene_lowvalue_hypercoag_test
    from merged_county_final
    group by bene_id_18900;
quit;

/* ================= 1. Encounter-level summary ================= */
proc sql;
    create table hypercoag_lvc_encounter_summary as
    select count(*) as N_Total_Encounters,
           sum(hypercoag_lvc) as N_LVC_Encounters,
           round(100 * calculated N_LVC_Encounters / calculated N_Total_Encounters, 0.1) as Pct_LVC_Encounters
    from merged_county_final;
quit;

proc print data=hypercoag_lvc_encounter_summary noobs label;
    label N_Total_Encounters = "N Total Encounters"
          N_LVC_Encounters   = "N Low-Value Hypercoagulability Tests"
          Pct_LVC_Encounters = "% of All Encounters";
run;

/* ================= 2. Beneficiary-level summary, restricted to those with a raw-flagged test ================= */
proc sql;
    create table hypercoag_lvc_bene_summary as
    select count(distinct a.bene_id_18900) as N_Total_Benes,
           sum(coalesce(b.bene_lowvalue_hypercoag_test,0)) as N_Bene_LVC,
           round(100 * calculated N_Bene_LVC / calculated N_Total_Benes, 0.1) as Pct_Bene_LVC
    from bene_latest_test as a
    left join bene_lowvalue_hypercoag as b
    on a.bene_id_18900 = b.bene_id_18900;
quit;

proc print data=hypercoag_lvc_bene_summary noobs label;
    label N_Total_Benes = "N Beneficiaries with Qualifying Test (Raw)"
          N_Bene_LVC    = "N with >=1 Low-Value Test"
          Pct_Bene_LVC  = "% with >=1 Low-Value Test";
run;

/* ================= 3. Funnel ================= */
proc sql;
    create table hypercoag_lvc_funnel as
    select 
        (select count(distinct bene_id_18900) from bene_latest_test) as N_Raw_Flagged,
        (select count(distinct bene_id_18900) from bene_2022_exclusion) as N_Excluded_2022,
        (select count(distinct bene_id_18900) from bene_2021_exclusion) as N_Excluded_2021,
        (select count(distinct bene_id_18900) from merged_county_final where hypercoag_lvc = 1) 
            as N_LVC_Final
    from merged_county_final (obs=1);
quit;

proc print data=hypercoag_lvc_funnel noobs label;
    label N_Raw_Flagged    = "N Beneficiaries with Qualifying Test (Raw)"
          N_Excluded_2022  = "N Excluded via 2022 Acute/Chronic Check"
          N_Excluded_2021  = "N Excluded via 2021 Acute/Chronic Check"
          N_LVC_Final      = "N Remaining (Final LVC)";
run;

/* ================= 4. Beneficiary-level rollup with size_of_plan/cat ================= */
proc sql;
    create table bene_hypercoag_lvc_plan as
    select a.bene_id_18900,
           coalesce(b.bene_lowvalue_hypercoag_test, 0) as any_hypercoag_lvc_test,
           max(a.size_of_plan) as size_of_plan,
           max(a.cat) as cat
    from merged_county_final as a
    inner join bene_latest_test as c on a.bene_id_18900 = c.bene_id_18900
    left join bene_lowvalue_hypercoag as b on a.bene_id_18900 = b.bene_id_18900
    group by a.bene_id_18900, b.bene_lowvalue_hypercoag_test;
quit;

/* ---- By size_of_plan ---- */
proc sql;
    create table hypercoag_lvc_by_size as
    select size_of_plan,
           count(distinct bene_id_18900) as N_Total,
           sum(any_hypercoag_lvc_test) as N_LVC,
           round(100 * calculated N_LVC / calculated N_Total, 0.1) as Pct_LVC
    from bene_hypercoag_lvc_plan
    group by size_of_plan;
quit;

proc print data=hypercoag_lvc_by_size noobs label;
    label size_of_plan = "Plan Size"
          N_Total       = "N Individuals with Qualifying Test"
          N_LVC         = "N with Low-Value Test"
          Pct_LVC       = "% with Low-Value Test";
run;

/* ---- By cat ---- */
proc sql;
    create table hypercoag_lvc_by_cat as
    select cat,
           count(distinct bene_id_18900) as N_Total,
           sum(any_hypercoag_lvc_test) as N_LVC,
           round(100 * calculated N_LVC / calculated N_Total, 0.1) as Pct_LVC
    from bene_hypercoag_lvc_plan
    group by cat;
quit;

proc print data=hypercoag_lvc_by_cat noobs label;
    label cat     = "Category"
          N_Total = "N Individuals with Qualifying Test"
          N_LVC   = "N with Low-Value Test"
          Pct_LVC = "% with Low-Value Test";
run;

/* ---- By size_of_plan x cat ---- */
proc sql;
    create table hypercoag_lvc_by_size_cat as
    select size_of_plan, cat,
           count(distinct bene_id_18900) as N_Total,
           sum(any_hypercoag_lvc_test) as N_LVC,
           round(100 * calculated N_LVC / calculated N_Total, 0.1) as Pct_LVC
    from bene_hypercoag_lvc_plan
    group by size_of_plan, cat;
quit;

proc print data=hypercoag_lvc_by_size_cat noobs label;
    label size_of_plan = "Plan Size"
          cat           = "Category"
          N_Total       = "N Individuals with Qualifying Test"
          N_LVC         = "N with Low-Value Test"
          Pct_LVC       = "% with Low-Value Test";
run;
