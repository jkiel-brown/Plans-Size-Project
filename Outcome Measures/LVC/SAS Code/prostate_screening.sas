/* ---- Open the saved dataset ---- */
libname outlib "P:\cahpr\jkiel1\Plans Project\Output";

data merged_county_final;
    set outlib.merged_county_final;
run;

/* ================= Step 1: raw prostate screening flag ================= */
data merged_county_final;
    set merged_county_final;

    array proc{5} $ hbrchcp1-hbrchcp5;

    prostate_screen_raw = 0;

    do i = 1 to 5;
        if proc{i} in ("84153","G0103","84152","84154") then prostate_screen_raw = 1;
    end;

    drop i;
run;

/* ================= Step 2: earliest prostate screening claim date, per beneficiary ================= */
proc sql;
    create table bene_first_prostate_screen as
    select bene_id_18900, min(hbfrom) as first_prostate_screen_date format=date9.
    from merged_county_final
    where prostate_screen_raw = 1
    group by bene_id_18900;
quit;

/* ================= Step 3: check ALL claims before that date for C61 diagnosis ================= */
proc sql;
    create table claims_first_pscreen as
    select a.*, b.first_prostate_screen_date
    from merged_county_final as a
    inner join bene_first_prostate_screen as b
    on a.bene_id_18900 = b.bene_id_18900;
quit;

data claims_b_p_scr_flagged;
    set claims_first_pscreen;

    array diag{5} $ hbdiag1-hbdiag5;

    prostate_exclusion_dx = 0;

    if hbfrom < first_prostate_screen_date then do;
        do i = 1 to 5;
            if substr(diag{i},1,3) = "C61" then prostate_exclusion_dx = 1;
        end;
    end;

    drop i;
run;

proc sql;
    create table bene_prostate_exclusion_before as
    select bene_id_18900, max(prostate_exclusion_dx) as prostate_exclusion_before
    from claims_b_p_scr_flagged
    group by bene_id_18900;
quit;

/* ---- Recode: if C61 found before first prostate screening, zero out ALL that beneficiary's screening flags ---- */
proc sql;
    create table merged_county_final as
    select a.*, coalesce(b.prostate_exclusion_before, 0) as prostate_exclusion_before
    from merged_county_final as a
    left join bene_prostate_exclusion_before as b
    on a.bene_id_18900 = b.bene_id_18900;
quit;

data merged_county_final;
    set merged_county_final;
    if prostate_exclusion_before = 1 then prostate_screen_step2 = 0;
    else prostate_screen_step2 = prostate_screen_raw;
run;

/* ================= Step 4: unique list of beneficiaries still flagged ================= */
proc sql;
    create table bene_still_prostate_screened as
    select distinct bene_id_18900
    from merged_county_final
    where prostate_screen_step2 = 1;
quit;

/* ================= Step 5: match onto Hballenc_updated_2021, check ALL 2021 claims for C61 ================= */
data claims_2021_prostate_filtered;
    if _n_ = 0 then set bene_still_prostate_screened (keep=bene_id_18900);

    if _n_ = 1 then do;
        declare hash hb(dataset:"bene_still_prostate_screened(keep=bene_id_18900)");
        hb.defineKey("bene_id_18900");
        hb.defineDone();
    end;

    set claims.Hballenc_updated_2021 (keep=bene_id_18900 hbdiag0-hbdiag4);

    if hb.check() ne 0 then delete;
run;

data claims_2021_prostate_flagged;
    set claims_2021_prostate_filtered;

    array diag21{5} $ hbdiag0-hbdiag4;

    prostate_exclusion_2021 = 0;

    do i = 1 to 5;
        if substr(diag21{i},1,3) = "C61" then prostate_exclusion_2021 = 1;
    end;

    drop i;
run;

proc sql;
    create table bene_prostate_exclusion_2021 as
    select distinct bene_id_18900
    from claims_2021_prostate_flagged
    where prostate_exclusion_2021 = 1;
quit;

/* ================= Step 6: recode -- anyone on the 2021 exclusion list gets ALL prostate screenings set to 0 ================= */
proc sql;
    create table merged_county_final as
    select a.*, 
           case when b.bene_id_18900 is not null then 1 else 0 end as prostate_exclusion_2021
    from merged_county_final as a
    left join bene_prostate_exclusion_2021 as b
    on a.bene_id_18900 = b.bene_id_18900;
quit;

data merged_county_final;
    set merged_county_final;
    if prostate_exclusion_2021 = 1 then prostate_screen_step3 = 0;
    else prostate_screen_step3 = prostate_screen_step2;
run;

/* ================= Step 7: final flag -- age >75 requirement applied last ================= */
data merged_county_final;
    set merged_county_final;
    if hkage > 75 then prostate_lowvalue_screen = prostate_screen_step3;
    else prostate_lowvalue_screen = 0;
run;

/* ================= Beneficiary-level: anyone with at least one LVC prostate screening ================= */
proc sql;
    create table bene_lowvalue_prostate as
    select bene_id_18900, max(prostate_lowvalue_screen) as bene_lowvalue_prostate_screen
    from merged_county_final
    group by bene_id_18900;
quit;


/* ================= 1. Encounter-level summary ================= */
proc sql;
    create table prostate_lvc_encounter_summary as
    select count(*) as N_Total_Encounters,
           sum(prostate_lowvalue_screen) as N_LVC_Encounters,
           round(100 * calculated N_LVC_Encounters / calculated N_Total_Encounters, 0.1) as Pct_LVC_Encounters
    from merged_county_final;
quit;

proc print data=prostate_lvc_encounter_summary noobs label;
    label N_Total_Encounters = "N Total Encounters"
          N_LVC_Encounters   = "N Low-Value Prostate Screenings"
          Pct_LVC_Encounters = "% of All Encounters";
run;

/* ================= 2. Beneficiary-level summary, restricted to eligible population (age >75) ================= */
proc sql;
    create table bene_prostate_lvc_elig as
    select bene_id_18900,
           max(prostate_lowvalue_screen) as bene_prostate_lvc_screen
    from merged_county_final
    where hkage > 75
    group by bene_id_18900;
quit;

proc sql;
    create table prostate_lvc_bene_summary as
    select count(distinct bene_id_18900) as N_Total_Benes,
           sum(bene_prostate_lvc_screen) as N_Bene_LVC,
           round(100 * calculated N_Bene_LVC / calculated N_Total_Benes, 0.1) as Pct_Bene_LVC
    from bene_prostate_lvc_elig;
quit;

proc print data=prostate_lvc_bene_summary noobs label;
    label N_Total_Benes = "N Eligible Beneficiaries (Age >75)"
          N_Bene_LVC    = "N with >=1 Low-Value Prostate Screening"
          Pct_Bene_LVC  = "% with >=1 Low-Value Screening";
run;

/* ================= 3. Funnel ================= */
proc sql;
    create table prostate_lvc_funnel as
    select 
        (select count(distinct bene_id_18900) from merged_county_final where prostate_screen_raw = 1) 
            as N_Raw_Screened,
        (select count(distinct bene_id_18900) from merged_county_final where prostate_screen_step2 = 1) 
            as N_After_2022_Exclusion,
        (select count(distinct bene_id_18900) from merged_county_final where prostate_screen_step3 = 1) 
            as N_After_2021_Exclusion,
        (select count(distinct bene_id_18900) from merged_county_final where prostate_lowvalue_screen = 1) 
            as N_After_Age_Restriction
    from merged_county_final (obs=1);
quit;

proc print data=prostate_lvc_funnel noobs label;
    label N_Raw_Screened          = "N Beneficiaries Screened (Raw)"
          N_After_2022_Exclusion  = "N Remaining After 2022 Lookback Exclusion"
          N_After_2021_Exclusion  = "N Remaining After 2021 Lookback Exclusion"
          N_After_Age_Restriction = "N Remaining After Age >75 Restriction (Final LVC)";
run;

/* ================= 4. Beneficiary-level rollup with size_of_plan/cat ================= */
proc sql;
    create table bene_prostate_lvc_plan as
    select bene_id_18900,
           max(prostate_lowvalue_screen) as any_prostate_lvc_screen,
           max(size_of_plan) as size_of_plan,
           max(cat) as cat
    from merged_county_final
    where hkage > 75
    group by bene_id_18900;
quit;

/* ---- By size_of_plan ---- */
proc sql;
    create table prostate_lvc_by_size as
    select size_of_plan,
           count(distinct bene_id_18900) as N_Total,
           sum(any_prostate_lvc_screen) as N_LVC,
           round(100 * calculated N_LVC / calculated N_Total, 0.1) as Pct_LVC
    from bene_prostate_lvc_plan
    group by size_of_plan;
quit;

proc print data=prostate_lvc_by_size noobs label;
    label size_of_plan = "Plan Size"
          N_Total       = "N Eligible Individuals (Age >75)"
          N_LVC         = "N with Low-Value Prostate Screening"
          Pct_LVC       = "% with Low-Value Screening";
run;

/* ---- By cat ---- */
proc sql;
    create table prostate_lvc_by_cat as
    select cat,
           count(distinct bene_id_18900) as N_Total,
           sum(any_prostate_lvc_screen) as N_LVC,
           round(100 * calculated N_LVC / calculated N_Total, 0.1) as Pct_LVC
    from bene_prostate_lvc_plan
    group by cat;
quit;

proc print data=prostate_lvc_by_cat noobs label;
    label cat     = "Category"
          N_Total = "N Eligible Individuals (Age >75)"
          N_LVC   = "N with Low-Value Prostate Screening"
          Pct_LVC = "% with Low-Value Screening";
run;

/* ---- By size_of_plan x cat ---- */
proc sql;
    create table prostate_lvc_by_size_cat as
    select size_of_plan, cat,
           count(distinct bene_id_18900) as N_Total,
           sum(any_prostate_lvc_screen) as N_LVC,
           round(100 * calculated N_LVC / calculated N_Total, 0.1) as Pct_LVC
    from bene_prostate_lvc_plan
    group by size_of_plan, cat;
quit;

proc print data=prostate_lvc_by_size_cat noobs label;
    label size_of_plan = "Plan Size"
          cat           = "Category"
          N_Total       = "N Eligible Individuals (Age >75)"
          N_LVC         = "N with Low-Value Prostate Screening"
          Pct_LVC       = "% with Low-Value Screening";
run;
