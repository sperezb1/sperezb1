* ECON 151 FINAL RESEARCH PAPER
* Title: 
* Author: Sofia Perez Barrios, Swarthmore College
* Due date: May 16, 2025


* Step 1: upload deforestation data from FAOSTAT, keep relevant variables
import delimited "/Users/HP/Documents/ECON 151 FINAL PROJECT/trade-deforestation/FAOSTAT_data_en_4-29-2025.csv", clear
rename * , lower
keep area itemcode yearcode year value
tostring itemcode, replace //need this in order to reshape
rename area country
rename value land_area  // Rename for clarity
label variable land_area "Land area (hectares)"

//reshape
collapse (sum) land_area, by(country year item)
reshape wide land_area, i(country year) j(item) string

save faostat_temp, replace


* Step 2: upload trade data from UN Comtrade, rename for consistency
import delimited "/Users/HP/Documents/ECON 151 FINAL PROJECT/trade-deforestation/TradeData_4_29_2025_21_32_17.csv", clear
rename * , lower
keep refyear reporterdesc partnerdesc primaryvalue cmdcode
tostring cmdcode, replace
rename refyear year
rename reporterdesc country
rename partnerdesc importer
rename cmdcode commoditycode
rename primaryvalue trade_value
label variable trade_value "Bilateral trade value (USD)"

//reshape the data
collapse (sum) trade_value, by(country year commoditycode)
reshape wide trade_value, i(country year) j(commoditycode) string
save trade_reshaped, replace

* Step 3: merge deforestation data + trade data
merge 1:1 country year using faostat_temp
tab _merge
//Keep only matched observations
keep if _merge == 3
drop _merge
save merged_trade_landuse, replace

* Step 4: Upload controls (climate policy stringency and GDP)
// Upload country climate policy stringency 
import excel "/Users/HP/Documents/ECON 151 FINAL PROJECT/trade-deforestation/qog_ei_ts_sept21.xlsx", sheet("Sheet1") firstrow clear
rename cname original_country
gen cname = lower(original_country) // Convert to lowercase for matching
local target_countries "argentina ecuador colombia brazil paraguay uruguay bolivia peru chile"

// Keep only observations from target countries
keep if inlist(cname, "argentina", "ecuador", "colombia", "brazil", ///
    "paraguay", "uruguay", "bolivia", "peru", "chile")

* Restore country names as "country" variable
drop cname
rename original_country country

keep country ccl_exepp wvs_ameop year
label variable ccl_exepp "Number of climate change-related policies or other executive provisions"
label variable wvs_ameop "Active memberships in environmental organizations (%)"

save climate_policies_controls, replace

use merged_trade_landuse
merge 1:1 country year using climate_policies_controls
keep if _merge == 3
drop _merge
save merged_trade_landuse_climate, replace

// Uploading GPD data
import delimited "/Users/HP/Documents/ECON 151 FINAL PROJECT/trade-deforestation/P_Data_Extract_From_World_Development_Indicators (1)/3e8d3792-21e2-4f95-b437-0d6323c0acd3_Data.csv", clear
foreach v of varlist yr* {
    capture confirm numeric variable `v'
    if _rc {
        destring `v', replace ignore("..")
    }
}
reshape long yr, i(seriesname seriescode countryname countrycode) j(year)

rename yr gdp_pc_usd
rename countryname country
label variable gdp_pc_usd "GDP per capita (current US$)"
label variable year "Year"

save "gdp_long_format", replace

use merged_trade_landuse_climate
merge 1:1 country year using gdp_long_format
keep if _merge == 3
drop _merge
save merged_trade_landuse_controls, replace

* Step 5: Regressions
//5.1: Prepare setup for panel structure, agreggate trade
* Set panel structure
encode countrycode, gen(countrynum)
xtset countrynum year

* Create total trade variable by summing all trade_value* columns
egen total_trade = rowtotal(trade_value*)

label variable total_trade "Total trade value (USD)"

//5.2: Renaming and labeling variables for clarity and interpretation of results.

//renaming variables and labels for Land Use
rename land_area6621 arable_land
label variable arable_land "Total arable land (hectares)"

rename land_area6650 permanent_crops
label variable permanent_crops "Permanent crop land (hectares)"

rename land_area6655 permanent_meadows
label variable permanent_meadows "Permanent meadows and pastures (hectares)"

//renaming variables and labels for Commodities
rename trade_value707 cucumbers
label variable cucumbers "Cucumbers and gherkins; fresh or chilled"

rename trade_value803 bananas
label variable bananas "Bananas, including plantains; fresh or dried"

rename trade_value80440 avocados
label variable avocados "Fruit, edible; avocados, fresh or dried"

rename trade_value81010 strawberries
label variable strawberries "Fruit, edible; strawberries, fresh"

rename trade_value901 coffee
label variable coffee "Coffee, whether or not roasted or decaffeinated; husks and skins; coffee substitutes containing coffee in any proportion"

rename trade_value903 mate
label variable mate "Mate"

rename trade_value100111 wheat
label variable wheat "Cereals; wheat and meslin, durum wheat, seed"

rename trade_value1801 cocoa
label variable cocoa "Cocoa beans; whole or broken, raw or roasted"

rename trade_value2401 tobacco
label variable tobacco "Tobacco, unmanufactured; tobacco refuse"

rename trade_value80211 almonds
label variable almonds "Nuts, edible; almonds, fresh or dried, in shell"

rename trade_value905 vanilla
label variable vanilla "Vanilla"

*-------------------------------------------------------------

//--------------------------------------------------
//First table

//Aggregating the land use as a way to have more data
* Log-transform key variables
gen ln_trade = ln(total_trade)
gen ln_gdp = ln(gdp_pc_usd)

//regressing each type of land on total trade
xtreg arable_land ln_trade ln_gdp ccl_exepp i.year, fe robust
estimates store arable 
xtreg permanent_crops ln_trade ln_gdp ccl_exepp i.year, fe robust
estimates store crops
xtreg permanent_meadows ln_trade ln_gdp ccl_exepp i.year, fe robust
estimates store meadows
 // negative relation
 
 esttab arable crops meadows using "landuse_results.tex", replace ///
    booktabs ///
    b(3) se(3) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    label ///
    stats(r2 N, fmt(3 0) labels("R-squared" "Observations")) ///
    title("Impact of Trade on Different Land Use Types\label{tab:landuse}") ///
    mgroups("Dependent Variable", pattern(1 0 0) ///
        prefix(\multicolumn{@span}{c}{) suffix(}) ///
        span erepeat(\cmidrule(lr){@span})) ///
    varlabels(ln_trade "Log Trade Value" ///
              ln_gdp "Log GDP per capita" ///
              ccl_exepp "Climate Policy Stringency") ///
    addnotes("Standard errors in parentheses" ///
             "* p<0.10, ** p<0.05, *** p<0.01" ///
             "All models include year fixed effects") ///
    alignment(D{.}{.}{-1}) ///
    substitute(\_ _)
	
//---------------------------------
//Adding some additional controls
gen trade_openness = total_trade/gdp_pc_usd
label variable trade_openness "Trade Openness"
//regressing each type of land on total trade
xtreg arable_land trade_openness ln_gdp ccl_exepp i.year, fe robust
estimates store arable_openness
xtreg permanent_crops trade_openness ln_gdp ccl_exepp i.year, fe robust
estimates store crops_openness
xtreg permanent_meadows trade_openness ln_gdp ccl_exepp i.year, fe robust
estimates store meadows_openess

esttab arable_openness crops_openness meadows_openess using "openess_landuse_results.tex", replace ///
    booktabs ///
    b(%9.2e) se(%9.2e) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    label ///
    stats(r2 N, fmt(3 0) labels("R-squared" "Observations")) ///
    title("Impact of Trade Openness on Different Land Use Types\label{tab:landuse}") ///
    mgroups("Dependent Variable", pattern(1 0 0) ///
        prefix(\multicolumn{@span}{c}{) suffix(}) ///
        span erepeat(\cmidrule(lr){@span})) ///
    varlabels(ln_trade "Log Trade Value" ///
              ln_gdp "Log GDP per capita" ///
              ccl_exepp "Climate Policy Stringency") ///
    addnotes("Standard errors in parentheses" ///
             "* p<0.10, ** p<0.05, *** p<0.01" ///
             "All models include year fixed effects") ///
    alignment(D{.}{.}{-1}) ///
    substitute(\_ _)

//lagged independent variables
xtreg arable_land L.ln_trade ln_gdp ccl_exepp i.year, fe robust
estimates store lagged_arable
xtreg permanent_crops L.ln_trade ln_gdp ccl_exepp i.year, fe robust
estimates store lagged_crops
xtreg permanent_meadows L.ln_trade ln_gdp ccl_exepp i.year, fe robust
estimates store lagged_meadows

esttab lagged_arable lagged_crops lagged_meadows using "lagged_landuse_results.tex", replace ///
    booktabs ///
    b(%9.2e) se(%9.2e) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    label ///
    stats(r2 N, fmt(3 0) labels("R-squared" "Observations")) ///
    title("Impact of Trade Openness on Different Land Use Types using Lagged Effects\label{tab:landuse}") ///
    mgroups("Dependent Variable", pattern(1 0 0) ///
        prefix(\multicolumn{@span}{c}{) suffix(}) ///
        span erepeat(\cmidrule(lr){@span})) ///
    varlabels(ln_trade "Log Trade Value" ///
              ln_gdp "Log GDP per capita" ///
              ccl_exepp "Climate Policy Stringency") ///
    addnotes("Standard errors in parentheses" ///
             "* p<0.10, ** p<0.05, *** p<0.01" ///
             "All models include year fixed effects") ///
    alignment(D{.}{.}{-1}) ///
    substitute(\_ _)


//second table - MANUALLY CALCULATING THE REGRESSIONS FOR EACH LAND AND COMMODITY
* Sum all land types (arable + permanent crops + meadows)
egen total_land = rowtotal(arable_land permanent_crops permanent_meadows)
label variable total_land "Total land in use (hectares)"
local land_types total_land arable_land permanent_crops permanent_meadows
local commodities wheat cocoa tobacco bananas avocados coffee mate vanilla almonds strawberries cucumbers

* Set panel structure (adjust 'country' and 'year' as needed)
xtset countrynum year

* Run each commodity using a loop with fixed effects and robust SEs
local commodities wheat cocoa tobacco bananas avocados coffee mate vanilla almonds strawberries cucumbers
foreach var of local commodities {
    display "Running regression for `var'"
    xtreg total_land `var' ln_gdp ccl_exepp, fe robust
    estimates store land_`var'
}

foreach var of local commodities {
    display "Running regression for `var'"
    xtreg arable_land `var' ln_gdp ccl_exepp, fe robust
    estimates store arbl_`var'
}

foreach var of local commodities {
    display "Running regression for `var'"
    xtreg permanent_crops `var' ln_gdp ccl_exepp, fe robust
    estimates store crops_`var'
}

foreach var of local commodities {
    display "Running regression for `var'"
    xtreg permanent_meadows `var' ln_gdp ccl_exepp, fe robust
    estimates store meadows_`var'
}
* Total Land regressions
esttab land_wheat land_cocoa land_tobacco land_bananas land_avocados land_coffee land_mate land_vanilla land_almonds land_strawberries land_cucumbers ///
    using total_land_table.tex, replace ///
    title("Commodity Effects on Total Land Use") ///
    b(%9.2e) se(%9.2e) star(* 0.10 ** 0.05 *** 0.01) ///
    coeflabels(wheat "Wheat" cocoa "Cocoa" tobacco "Tobacco" bananas "Bananas" avocados "Avocados" ///
               coffee "Coffee" mate "Mate" vanilla "Vanilla" almonds "Almonds" strawberries "Strawberries" cucumbers "Cucumbers") ///

* Repeat for other land types:

esttab arbl_wheat arbl_cocoa arbl_tobacco arbl_bananas arbl_avocados arbl_coffee arbl_mate arbl_vanilla arbl_almonds arbl_strawberries arbl_cucumbers ///
    using arable_land_table.tex, replace ///
    title("Commodity Effects on Arable Land") ///
    b(%9.2e) se(%9.2e) star(* 0.10 ** 0.05 *** 0.01) ///
    coeflabels(wheat "Wheat" cocoa "Cocoa" tobacco "Tobacco" bananas "Bananas" avocados "Avocados" ///
               coffee "Coffee" mate "Mate" vanilla "Vanilla" almonds "Almonds" strawberries "Strawberries" cucumbers "Cucumbers") ///

esttab crops_wheat crops_cocoa crops_tobacco crops_bananas crops_avocados crops_coffee crops_mate crops_vanilla crops_almonds crops_strawberries crops_cucumbers ///
    using crops_land_table.tex, replace ///
    title("Commodity Effects on Permanent Crops Land") ///
    b(%9.2e) se(%9.2e) star(* 0.10 ** 0.05 *** 0.01) ///
    coeflabels(wheat "Wheat" cocoa "Cocoa" tobacco "Tobacco" bananas "Bananas" avocados "Avocados" ///
               coffee "Coffee" mate "Mate" vanilla "Vanilla" almonds "Almonds" strawberries "Strawberries" cucumbers "Cucumbers") ///

esttab meadows_wheat meadows_cocoa meadows_tobacco meadows_bananas meadows_avocados meadows_coffee meadows_mate meadows_vanilla meadows_almonds meadows_strawberries meadows_cucumbers ///
    using meadows_land_table.tex, replace ///
    title("Commodity Effects on Permanent Meadows Land") ///
    b(%9.2e) se(%9.2e) star(* 0.10 ** 0.05 *** 0.01)   
	coeflabels(wheat "Wheat" cocoa "Cocoa" tobacco "Tobacco" bananas "Bananas" avocados "Avocados" ///
               coffee "Coffee" mate "Mate" vanilla "Vanilla" almonds "Almonds" strawberries "Strawberries" cucumbers "Cucumbers") ///



//old code, reconsider--------------------------
* (1) Regression: total_land
xtreg total_land wheat cocoa tobacco bananas avocados coffee mate vanilla almonds strawberries cucumbers ln_gdp ccl_exepp, fe robust
estimates store total_land

* (2) Regression: arable_land
xtreg arable_land wheat cocoa tobacco bananas avocados coffee mate vanilla almonds strawberries cucumbers ln_gdp ccl_exepp, fe robust
estimates store arable_land

* (3) Regression: permanent_crops
xtreg permanent_crops total_tradewheat cocoa tobacco bananas avocados coffee mate vanilla almonds strawberries cucumbers ln_gdp ccl_exepp, fe robust
estimates store permanent_crops

* (4) Regression: permanent_meadows
xtreg permanent_meadows wheat cocoa tobacco bananas avocados coffee mate vanilla almonds strawberries cucumbers ln_gdp ccl_exepp, fe robust
estimates store permanent_meadows

* Export all results to a LaTeX table
esttab total_land arable_land permanent_crops permanent_meadows ///
    using "land_regressions.tex", replace ///
    b(%9.3f) se(%9.3f) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    label booktabs ///
    title(Fixed Effects Regressions of Land Types on Commodities, GDP, and Climate Policy) ///
    indicate("Country FE = _cons") ///
    addnotes("Robust standard errors in parentheses." "*** p<0.01, ** p<0.05, * p<0.10")

//now we regress with each commodity
*Log-transform for each commodity 
foreach var in wheat cocoa tobacco bananas avocados coffee mate vanilla almonds strawberries cucumbers {
    gen ln_`var' = ln(`var' + 1)  // +1 to handle zeros
}

local commodities wheat cocoa tobacco bananas avocados coffee mate vanilla almonds strawberries cucumbers

foreach comm of local commodities {
    * Fixed effects regression
    xtreg total_land ln_`comm' ln_gdp ccl_exepp wvs_ameop i.year, fe robust

    * Store results
    estimates store model_`comm'
}

//old code ends---------------------------------

//doing regressions with log (so numbers are more visible)
* (1) Regression: total_land
xtreg total_land ln_wheat ln_cocoa ln_bananas ln_avocados ln_coffee ln_mate ln_vanilla ln_almonds ln_strawberries ln_cucumbers ln_gdp ccl_exepp, fe robust
estimates store log_total_land

* (2) Regression: arable_land
xtreg arable_land ln_wheat ln_cocoa ln_bananas ln_avocados ln_coffee ln_mate ln_vanilla ln_almonds ln_strawberries ln_cucumbers ln_gdp ccl_exepp, fe robust
estimates store log_arable_land

* (3) Regression: permanent_crops
xtreg permanent_crops ln_wheat ln_cocoa ln_bananas ln_avocados ln_coffee ln_mate ln_vanilla ln_almonds ln_strawberries ln_cucumbers ln_gdp ccl_exepp, fe robust
estimates store log_permanent_crops

* (4) Regression: permanent_meadows
xtreg permanent_meadows ln_wheat ln_cocoa ln_bananas ln_avocados ln_coffee ln_mate ln_vanilla ln_almonds ln_strawberries ln_cucumbers ln_gdp ccl_exepp, fe robust
estimates store log_permanent_meadows

* Export all results to a LaTeX table
esttab log_total_land log_arable_land log_permanent_crops log_permanent_meadows ///
    using "logland_regressions.tex", replace ///
    b(%9.3f) se(%9.3f) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    label booktabs ///
    title(Fixed Effects Regressions of Land Types on Commodities, GDP, and Climate Policy) ///
    indicate("Country FE = _cons") ///
    addnotes("Robust standard errors in parentheses." "*** p<0.01, ** p<0.05, * p<0.10")

//just to check: does climate stringency have an impact on deforestation?
* (1) Regression: total_land
xtreg total_land ccl_exepp ln_gdp total_trade, fe robust // negative correlation


//OLD Second table

* Sum all land types (arable + permanent crops + meadows)
egen total_land = rowtotal(arable_land permanent_crops permanent_meadows)
label variable total_land "Total land in use (hectares)"
//regressing the aggregate land
xtreg total_land ln_trade ln_gdp ccl_exepp i.year, fe robust
estimates store model_total_trade

//now we regress with each commodity
*Log-transform for each commodity 
foreach var in wheat cocoa tobacco bananas avocados coffee mate vanilla almonds strawberries cucumbers {
    gen ln_`var' = ln(`var' + 1)  // +1 to handle zeros
}

local commodities wheat cocoa tobacco bananas avocados coffee mate vanilla almonds strawberries cucumbers

foreach comm of local commodities {
    * Fixed effects regression
    xtreg total_land ln_`comm' ln_gdp ccl_exepp wvs_ameop i.year, fe robust

    * Store results
    estimates store model_`comm'
}

estimates dir 

* Commodity models for total land
local total_models ""
foreach comm in `commodities' {
    local total_models `total_models' total_`comm'
}

esttab `total_models' arable crops meadows using "landuse_results.tex", replace ///
    booktabs ///
    b(3) se(3) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(ln_* ln_gdp ccl_exepp) ///
    order(ln_wheat ln_cocoa ln_tobacco ln_bananas ln_avocados ln_coffee ///
          ln_mate ln_vanilla ln_almonds ln_strawberries ln_cucumbers ln_trade) ///
    stats(r2 N, fmt(2 0)) ///
    varlabels(ln_trade "Total Trade" ///
              ln_wheat "Wheat" ///
              ln_cocoa "Cocoa" ///
              ln_tobacco "Tobacco" ///
              ln_bananas "Bananas" ///
              ln_avocados "Avocados" ///
              ln_coffee "Coffee" ///
              ln_mate "Mate" ///
              ln_vanilla "Vanilla" ///
              ln_almonds "Almonds" ///
              ln_strawberries "Strawberries" ///
              ln_cucumbers "Cucumbers" ///
              ln_gdp "Log GDP pc" ///
              ccl_exepp "Climate Policy") ///
    title("Land Use Determinants\label{tab:landuse}") ///
    mgroups("Total Land by Commodity" "Arable Land" "Permanent Crops" "Permanent Meadows", ///
            pattern(1 0 0 0) ///
            prefix(\multicolumn{@span}{c}{) suffix(}) ///
            span erepeat(\cmidrule(lr){@span})) ///
    addnotes("All models include year and country fixed effects." ///
             "Robust standard errors in parentheses." ///
             "* p<0.10, ** p<0.05, *** p<0.01") ///
    compress ///
    prehead("\begin{table}[htbp]\centering\scriptsize") ///
    postfoot("\end{table}")






* Revised regression storage with shorter names
estimates clear
foreach comm of local commodities {
    foreach land in total arable crops meadows {
        xtreg `land'_land ln_`comm' ln_gdp ccl_exepp i.year, fe robust
        estimates store `land'_`comm'  // Shorter names
    }
}
* Prepare table with 4 land type columns per commodity
* Build lists of stored estimates
local total_models ""
local arable_models ""
local crops_models ""
local meadows_models ""

foreach comm in wheat cocoa_beans tobacco bananas avocados coffee_beans mate vanilla almonds strawberries cucumbers{ 
    local total_models `total_models' total_land_`comm'
    local arable_models `arable_models' arable_land_`comm'
    local crops_models `crops_models' permanent_crops_`comm'
    local meadows_models `meadows_models' permanent_meadows_`comm'
}

esttab `total_models' `arable_models' `crops_models' `meadows_models' ///
    using "landuse_results.tex", replace ///
    booktabs ///
    b(3) se(3) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(ln_* ln_gdp ccl_exepp) ///
    stats(r2 N, fmt(2 0)) ///
    mgroups("Total Land" "Arable Land" "Permanent Crops" "Permanent Meadows", ///
        pattern(1 1 1 1) ///
        prefix(\multicolumn{@span}{c}{) suffix(}) ///
        span erepeat(\cmidrule(lr){@span})) ///
    varlabels(ln_gdp "Log GDP pc" ccl_exepp "Climate Policy") ///
    title("Commodity Trade Effects by Land Use Type") ///
    compress

	
//regressing total land on each commodity
xtreg total_land ln_wheat ln_cocoa_beans ln_tobacco ln_bananas ln_avocados ln_coffee_beans ln_mate ln_vanilla ln_almonds ln_strawberries ln_cucumbers ln_gdp i.year, fe robust
estimates store combined_model


//----------------------------------------------



//another approach

* Create deforestation measures for each land type
foreach land in arable_land permanent_crops permanent_meadows {
    bysort countrynum (year): gen `land'_loss = `land'[_n-1] - `land'
    label variable `land'_loss "Annual `land' loss (hectares)"
}

* Log-transform trade

foreach var in wheat cocoa_beans tobacco bananas avocados coffee_beans mate vanilla almonds strawberries cucumbers {
    gen ln_`var' = ln(`var' + 1)  // +1 to handle zeros
}
* Define commodities and land types
local commodities wheat cocoa_beans tobacco bananas avocados coffee_beans mate vanilla almonds strawberries cucumbers
local land_types arable permanent_crops permanent_meadows

* Loop through all combinations
foreach land of local land_types {
    foreach comm of local commodities {
        * Run fixed effects regression
        xtreg `land'_loss ln_`comm' ln_gdp ccl_exepp wvs_ameop i.year, fe robust
        
        * Store results
        estimates store `land'_`comm'
        
    }
}
* Table for arable land results
esttab arable_* using "arable_results.rtf", replace ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(ln_*) ///
    stats(r2 N, fmt(3 0)) ///
    title("Arable Land Loss Regression Results")

* Table for permanent crops results
esttab permanent_crops_* using "crops_results.rtf", replace ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(ln_*) ///
    stats(r2 N, fmt(3 0)) ///
    title("Permanent Crops Loss Regression Results")




	
	
	
	
	
	

//----USING FAOSTAT TRADE DATA--------

//step 1: upload deforestation data from FAOSTAT, keep relevant variables
import delimited "/Users/HP/Documents/ECON 151 FINAL PROJECT/trade-deforestation/FAOSTAT_data_en_4-29-2025.csv", clear
rename * , lower
keep area itemcode yearcode year value
tostring itemcode, replace //need this in order to reshape
rename area country
rename value land_area  // Rename for clarity
label variable land_area "Land area (hectares)"

//reshape
collapse (sum) land_area, by(country year item)
reshape wide land_area, i(country year) j(item) string

save faostat_temp2, replace


//step 2: upload trade data from FAOSTAT on exports in 1000 USD values, rename for consistency
import delimited "/Users/HP/Documents/ECON 151 FINAL PROJECT/trade-deforestation/FAOSTAT_data_export_values.csv", clear
rename * , lower
// Create proper string version of itemcode
generate item_str = string(itemcode, "%16.0f")  // Use itemcode instead of itemcodecpc
replace item_str = trim(item_str)

// Rename and label
rename area country
rename value USDvalue
label variable USDvalue "Export values in 1000 USD"

// Collapse and check for duplicates
collapse (sum) USDvalue, by(country year item_str)
duplicates report country year item_str  // Should show 1 observation per group

// Final reshape
reshape wide USDvalue, i(country year) j(item_str) string



//step 3: merge
merge 1:1 country year using faostat_temp2
tab _merge
//Keep only matched observations
keep if _merge == 3
drop _merge
save merged_trade_landuse2, replace

//step 3: upload controls: climate policy stringency and GDP
import excel "/Users/HP/Documents/ECON 151 FINAL PROJECT/trade-deforestation/qog_ei_ts_sept21.xlsx", sheet("Sheet1") firstrow clear
rename cname original_country
gen cname = lower(original_country) // Convert to lowercase for matching
local target_countries "argentina ecuador colombia brazil paraguay uruguay bolivia peru chile"

* Keep only observations from target countries
keep if inlist(cname, "argentina", "ecuador", "colombia", "brazil", ///
    "paraguay", "uruguay", "bolivia", "peru", "chile")

* Restore original country names
drop cname
rename original_country country

keep country ccl_exepp wvs_ameop year
label variable ccl_exepp "Number of climate change-related policies or other executive provisions"
label variable wvs_ameop "Active memberships in environmental organizations (%)"

save climate_policies_controls, replace

use merged_trade_landuse2
merge 1:1 country year using climate_policies_controls
keep if _merge == 3
drop _merge
save merged_trade_landuse_climate2, replace

//uploading GPD
import delimited "/Users/HP/Documents/ECON 151 FINAL PROJECT/trade-deforestation/P_Data_Extract_From_World_Development_Indicators (1)/3e8d3792-21e2-4f95-b437-0d6323c0acd3_Data.csv", clear
foreach v of varlist yr* {
    capture confirm numeric variable `v'
    if _rc {
        destring `v', replace ignore("..")
    }
}
reshape long yr, i(seriesname seriescode countryname countrycode) j(year)

rename yr gdp_pc_usd
rename countryname country
label variable gdp_pc_usd "GDP per capita (current US$)"
label variable year "Year"

save "gdp_long_format", replace

use merged_trade_landuse_climate2
merge 1:1 country year using gdp_long_format
keep if _merge == 3
drop _merge
save merged_trade_landuse_controls2, replace

//Step 4: Regressions
//4.1: Prepare setup for panel structure, agreggate trade
* Set panel structure
encode countrycode, gen(countrynum)
xtset countrynum year

* Create total trade variable by summing all trade_value* columns
egen total_trade = rowtotal(USDvalue*)

label variable total_trade "Total trade value in 1000 (USD)"

//4.2: Renaming and labeling variables for clarity and interpretation of results.
//renaming stuff
//renaming variables and labels for USD value exports
rename USDvalue1232 cucumbers
label variable cucumbers "Cucumbers and gherkins"

rename USDvalue1311 avocados
label variable avocados "Avocados"

rename USDvalue1312 bananas
label variable bananas "Bananas"

rename USDvalue21422 almonds
label variable almonds "Almonds, shelled"

rename USDvalue39120 wheat
label variable wheat "Bran of wheat"

rename USDvalue1610 coffee
label variable coffee "Coffee, green"

rename USDvalue1630 mate
label variable mate "Maté leaves"

rename USDvalue1354 strawberries
label variable strawberries "Strawberries"

rename USDvalue1970 tobacco
label variable tobacco "Unmanufactured tobacco"

rename USDvalue1658 vanilla
label variable vanilla "Vanilla, Raw"

rename USDvalue1640 cocoa
label variable cocoa "Cocoa beans"

//renaming variables and labels for Land Use
rename land_area6621 arable_land
label variable arable_land "Total arable land (hectares)"

rename land_area6650 permanent_crops
label variable permanent_crops "Permanent crop land (hectares)"

rename land_area6655 permanent_meadows
label variable permanent_meadows "Permanent meadows and pastures (hectares)"

*-------------------------------------------------------------

//--------------------------------------------------
//First table

//Aggregating the land use as a way to have more data
* Log-transform key variables
gen ln_trade = ln(total_trade)
gen ln_gdp = ln(gdp_pc_usd)

//regressing each type of land on total trade
xtreg arable_land ln_trade ln_gdp ccl_exepp i.year, fe robust
estimates store arable 
xtreg permanent_crops ln_trade ln_gdp ccl_exepp i.year, fe robust
estimates store crops
xtreg permanent_meadows ln_trade ln_gdp ccl_exepp i.year, fe robust
estimates store meadows

//second table - MANUALLY CALCULATING THE REGRESSIONS FOR EACH LAND AND COMMODITY
* Sum all land types (arable + permanent crops + meadows)
egen total_land = rowtotal(arable_land permanent_crops permanent_meadows)
label variable total_land "Total land in use (hectares)"
local land_types total_land arable_land permanent_crops permanent_meadows
local commodities wheat cocoa tobacco bananas avocados coffee mate vanilla almonds strawberries cucumbers

* Set panel structure (adjust 'country' and 'year' as needed)
xtset countrynum year

* Run each regression manually with fixed effects and robust SEs

* (1) Regression: total_land
xtreg total_land wheat cocoa tobacco bananas avocados coffee mate vanilla almonds strawberries cucumbers ln_gdp ccl_exepp, fe robust
estimates store total_land


