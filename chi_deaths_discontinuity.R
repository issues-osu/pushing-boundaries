library(sociome)
library(ggplot2)
library(readr)
library(MASS)
library(sp)
library(stargazer)
library(matrixStats)
library(tidyverse)
library(scales)
library(tidycensus)
library(dplyr)
library(CARBayes)
library(sf)
library(spdep)
library(GGally)
library(dplyr)
library(httr)
library(jsonlite)
library(dplyr)
library(lubridate)
library(car)

# Socrata SQL API URL (already filtered for age < 18 and death_date in 2015–2023)
url <- "https://datacatalog.cookcountyil.gov/resource/cjeq-bs86.json?$query=SELECT%0A%20%20%60casenumber%60%2C%0A%20%20%60incident_date%60%2C%0A%20%20%60death_date%60%2C%0A%20%20%60age%60%2C%0A%20%20%60gender%60%2C%0A%20%20%60race%60%2C%0A%20%20%60latino%60%2C%0A%20%20%60manner%60%2C%0A%20%20%60primarycause%60%2C%0A%20%20%60primarycause_linea%60%2C%0A%20%20%60primarycause_lineb%60%2C%0A%20%20%60primarycause_linec%60%2C%0A%20%20%60secondarycause%60%2C%0A%20%20%60gunrelated%60%2C%0A%20%20%60opioids%60%2C%0A%20%20%60cold_related%60%2C%0A%20%20%60heat_related%60%2C%0A%20%20%60commissioner_district%60%2C%0A%20%20%60incident_street%60%2C%0A%20%20%60incident_city%60%2C%0A%20%20%60incident_zip%60%2C%0A%20%20%60longitude%60%2C%0A%20%20%60latitude%60%2C%0A%20%20%60location%60%2C%0A%20%20%60residence_city%60%2C%0A%20%20%60residence_zip%60%2C%0A%20%20%60objectid%60%2C%0A%20%20%60chi_ward%60%2C%0A%20%20%60chi_commarea%60%2C%0A%20%20%60covid_related%60%0AWHERE%0A%20%20(%60age%60%20%3C%2018)%0A%20%20AND%20%60death_date%60%0A%20%20%20%20%20%20%20%20BETWEEN%20%222015-01-01T00%3A00%3A01%22%20%3A%3A%20floating_timestamp%0A%20%20%20%20%20%20%20%20AND%20%222023-12-31T23%3A59%3A00%22%20%3A%3A%20floating_timestamp%0AORDER%20BY%20%60casenumber%60%20DESC%20NULL%20FIRST"

response <- GET(url)
stop_for_status(response)

data_raw <- content(response, as = "text", encoding = "UTF-8")
child_deaths <- fromJSON(data_raw, flatten = TRUE)

deaths <- child_deaths %>%
  mutate(death_date = ymd_hms(
    death_date, quiet = TRUE
    ),
  incident_date = ymd_hms(
    incident_date, quiet = TRUE),
    age = as.numeric(age)
  )

# Inspect
glimpse(deaths)

vars_census <- c(
  "P001001", 
  "P012006", 
  "P012007", 
  "P012008", 
  "P012009", 
  "P012010",
  "P012011",
  "P012012", 
  "P005003", 
  "P005004", 
  "P005006", 
  "P005010",
  "P015001", 
  "P005005", 
  "P005007", 
  "P005008", 
  "P005009"
  )

chi_sf1 <- tidycensus::get_decennial(
  geography = "tract", 
  state = "IL",
  county = "Cook",
  variables = vars_census,
  year = 2010, 
  output = "wide", 
  geometry = TRUE
  )

vars_acs <- c(
  "C24010_004E", "C24010_040E", 
  "C24010_001E", "B23025_005E", 
  "B23025_003E", "B17021_001E", 
  "B17021_002E", "B15002_011E", 
  "B15002_028E", "B15002_001E",  
  "B11003_016E", "B11001_001E", 
  "B25001_001E", "B25003_003E", 
  "B25002_002E", "B25002_003E", 
  "B16004_001E", "B16004_006E", 
  "B16004_007E", "B16004_008E",
  "B16004_011E", "B16004_012E", 
  "B16004_013E", "B16004_016E", 
  "B16004_017E", "B16004_018E", 
  "B16004_021E", "B16004_022E", 
  "B16004_023E", "B16004_028E",
  "B16004_029E", "B16004_030E", 
  "B16004_033E", "B16004_034E", 
  "B16004_035E", "B16004_038E", 
  "B16004_039E", "B16004_040E", 
  "B16004_043E", "B16004_044E",
  "B16004_045E", "B16004_050E", 
  "B16004_051E", "B16004_052E", 
  "B16004_055E", "B16004_056E", 
  "B16004_057E", "B16004_060E", 
  "B16004_061E", "B16004_062E",
  "B16004_065E", "B16004_066E", 
  "B16004_067E", "B16004_008E", 
  "B16004_013E", "B16004_018E", 
  "B16004_023E", "B16004_030E",
  "B16004_035E", "B16004_040E", 
  "B16004_045E", "B16004_052E", 
  "B16004_057E", "B16004_062E", 
  "B16004_067E", "B16004_001E", 
  "B25038_004E", "B25038_011E",
  "B15002_015E", "B15002_016E", 
  "B15002_017E", "B15002_018E",
  "B15002_032E", "B15002_033E", 
  "B15002_034E", "B15002_035E"
  
)

chi_acs <- tidycensus::get_acs(
  geography = "tract", 
  state = "IL",
  county = "Cook",
  variables = vars_acs, 
  year = 2015, 
  output = "wide"
  )

f_index <- function(x) 1 - rowSums(x^2)

fac <- function(x, factors, rotation = "varimax", scores = "regression") {
  ok <- complete.cases(x)
  fa <- factanal(x[ok,], factors, rotation=rotation, scores=scores)
  score <- rep(NA, fa$n.obs + sum(!ok))
  score[ok] <- fa$scores
  return(score)
}

chi_sf1 <- chi_sf1 %>%
  transmute(
    BG_CODE = GEOID,
    pop = P001001,
    hh = P015001,
    race_white = P005003,
    race_black = P005004,
    race_asian = P005006,
    race_hisp = P005010,
    race_other = P005005 + P005007 + P005008 + P005009,
    p_race_white = race_white / pop,
    p_race_black = race_black / pop,
    p_race_asian = race_asian / pop,
    p_race_hisp = race_hisp / pop,
    p_race_other = race_other / pop,
    age_15_35_male = P012006 + 
      P012007 + 
      P012008 + 
      P012009 + 
      P012010 +
      P012011 + 
      P012012,
    hhi = f_index(cbind
      (
        p_race_white, 
        p_race_black, 
        p_race_asian,
        p_race_hisp, 
        p_race_other)
      ),
    geometry
  )

fac_with_loadings <- function(
    x, factors, rotation = "varimax", scores = "regression"
    ) {
  ok <- complete.cases(x)
  fa <- factanal(x[ok,], 
   factors, 
   rotation = rotation, 
   scores = scores
  )
  return(fa)   
}


chi_acs <- chi_acs %>%
  transmute(
    BG_CODE = GEOID,
    occ_management = C24010_004E + C24010_040E,
    occ_universe = C24010_001E,
    emp_unemployed = B23025_005E,
    emp_civ_lab_force = B23025_003E,
    poverty_universe = B17021_001E,
    poverty = B17021_002E,
    edu_hs = B15002_011E + B15002_028E,
    edu_universe = B15002_001E,
    hh_single_mother = B11003_016E,
    hh = B11001_001E,
    hu = B25001_001E,
    hu_occupied_renter = B25003_003E,
    hu_occupied = B25002_002E,
    hu_vacant = B25002_003E,
    lang_universe = B16004_001E,
    lang_eng_limited = # Speak Eng less than "very well"
      B16004_006E + B16004_007E + B16004_008E +
      B16004_011E + B16004_012E + B16004_013E +
      B16004_016E + B16004_017E + B16004_018E +
      B16004_021E + B16004_022E + B16004_023E +
      B16004_028E + B16004_029E + B16004_030E +
      B16004_033E + B16004_034E + B16004_035E +
      B16004_038E + B16004_039E + B16004_040E +
      B16004_043E + B16004_044E + B16004_045E +
      B16004_050E + B16004_051E + B16004_052E +
      B16004_055E + B16004_056E + B16004_057E +
      B16004_060E + B16004_061E + B16004_062E +
      B16004_065E + B16004_066E + B16004_067E,
    lang_eng_no = B16004_008E + B16004_013E + B16004_018E + B16004_023E +
      B16004_030E + B16004_035E + B16004_040E + B16004_045E +
      B16004_052E + B16004_057E + B16004_062E + B16004_067E,
    lang_universe = B16004_001E,
    housing_moved_2000_2009 = B25038_004E + B25038_011E,
    housing_moved_2000_2009 = B25038_004E + B25038_011E,
    p_occ_management = occ_management / occ_universe,
    p_emp_unemployed = emp_unemployed / emp_civ_lab_force,
    
    
    p_poverty = poverty / poverty_universe,
    p_edu_hs = edu_hs / edu_universe,
    p_single_mother = hh_single_mother / hh,
    p_hu_occupied_renter = hu_occupied_renter / hu_occupied,
    p_hu_vacant = hu_vacant / hu,
    p_lang_eng_limited = lang_eng_limited / lang_universe,
    p_lang_eng_no = lang_eng_no / lang_universe,
    p_housing_moved_2000_2009 = housing_moved_2000_2009 / hu_occupied,
    con_disadv = fac(
      cbind(
        p_occ_management, 
        p_emp_unemployed, 
        p_poverty,
        p_edu_hs, 
        p_single_mother
      ), factors=1
    ),
    res_instab = fac(
      cbind(
        p_hu_occupied_renter, 
        p_housing_moved_2000_2009,
        p_hu_vacant
        ), factors=1
      ),
    immi_con = rowMeans(
      cbind(
        p_lang_eng_limited, 
        p_lang_eng_no)
      )
  ) 


chi_acs <- chi_acs %>% 
  dplyr::select(
    BG_CODE, 
    con_disadv, 
    res_instab, 
    immi_con
    )

deaths <- deaths %>%
  mutate(
    latitude = as.numeric(latitude),
    longitude = as.numeric(longitude)
  ) %>%
  filter(
    !is.na(latitude) & !is.na(longitude)
    ) %>%
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326)

chi_sf1 <- st_transform(chi_sf1, crs = 4326)

deaths_with_bg <- st_join(deaths, chi_sf1[, "BG_CODE"], left = FALSE)

deaths <- deaths_with_bg %>%
  st_drop_geometry() %>%
  count(BG_CODE, name = "adi_infdeath")

chi_sf1 <- chi_sf1 %>%
  left_join(deaths, by = "BG_CODE") %>%
  dplyr::mutate(adi_infdeath = ifelse(is.na(adi_infdeath), 0, adi_infdeath))

chi_bg <- chi_sf1 %>% left_join(deaths, by = c("BG_CODE" = "BG_CODE"))
chi_bg <- chi_bg %>%  left_join(chi_acs, by = c("BG_CODE" = "BG_CODE"))

chi_bg <- chi_bg %>% select(BG_CODE, hh, adi_infdeath=adi_infdeath.x, con_disadv, immi_con, res_instab, pop)

chi_bg_sf <- st_as_sf(chi_bg)

adi <- get_adi(geography = "tract", state = "IL", county = "Cook", year = 2018, dataset = "acs5")
adi <- adi %>%
  dplyr::select(GEOID, Economic_Hardship_and_Inequality) %>%  
  dplyr::mutate(BG_CODE = GEOID) %>%
  right_join(chi_bg_sf)

chi_bg_sf <- adi
chi_bg_sf <- st_as_sf(chi_bg_sf)

chi_bg_sf <- chi_bg_sf[!st_is_empty(chi_bg_sf), ]

nb <- poly2nb(chi_bg_sf, row.names = chi_bg_sf$BG_CODE)
W_list <- nb2listw(nb, style = "B", zero.policy = TRUE)
W_mat <- nb2mat(nb, style = "B", zero.policy = TRUE)
con_disadv_vals <- chi_bg_sf$Economic_Hardship_and_Inequality

lm_check <- lm(adi_infdeath ~ con_disadv + res_instab + hh + immi_con, data = chi_bg)
vif(lm_check)

chi_bg_sf <- st_as_sf(chi_bg_sf)
chi_bg_sf <- st_as_sf(chi_bg_sf)  # if not already sf
chi_bg_sf <- chi_bg_sf[!st_is_empty(chi_bg_sf), ]


formula <- adi_infdeath ~ con_disadv + res_instab + immi_con

chi_bg_sf <- chi_bg_sf %>%
  filter(
    !is.na(con_disadv),
    !is.na(res_instab),
    !is.na(immi_con),
    !is.na(Economic_Hardship_and_Inequality)
  )

chi_bg_sf$EHI_decile <- ntile(chi_bg_sf$Economic_Hardship_and_Inequality, 10)

nb <- spdep::poly2nb(chi_bg_sf, row.names = chi_bg_sf$BG_CODE)
W <- spdep::nb2mat(nb, style = "B", zero.policy = TRUE)

Z.EHI <- as.matrix(dist(chi_bg_sf$EHI_decile, diag = TRUE, upper = TRUE))
Z.EHI <- Z.EHI / max(Z.EHI, na.rm = TRUE)

model <- S.CARdissimilarity(
  formula = formula,
  data = st_drop_geometry(chi_bg_sf),
  family = "poisson",
  W = W,
  Z = list(Z.EHI = Z.EHI),
  W.binary = TRUE,
  burnin = 20000,
  n.sample = 100000,
  thin= 10
)

print(model)
mcmc_samples <- as.data.frame(model$samples$beta)
colnames(mcmc_samples)

cor_matrix <- cor(mcmc_samples)
print(round(cor_matrix, 2))

ggpairs(
  mcmc_samples,
  lower = list(continuous = wrap("points", alpha = 0.2, size = 0.1)),
  diag = list(continuous = "densityDiag"),
  upper = list(continuous = wrap("cor", size = 3))
)
####################################### STOP
Z_mat <- as.matrix(dist(chi_bg_sf$Economic_Hardship_and_Inequality, diag = TRUE, upper = TRUE))
Z_mat <- Z_mat / max(Z_mat, na.rm = TRUE)  # Normalize to [0,1]

model <- S.CARdissimilarity(
  formula = formula,
  data = st_drop_geometry(chi_bg_sf),
  family = "poisson",
  W = W,
  Z = list(Z.EHI = Z_mat),
  W.binary = TRUE,
  burnin = 20000,
  n.sample = 100000,
  thin= 10
)

print(model)
###################################################
# Set threshold

# Create dissimilarity matrix Z.EHI based on threshold
Z.EHI <- as.matrix(dist(chi_bg_sf$Economic_Hardship_and_Inequality, diag = TRUE, upper = TRUE))
Z.EHI <- Z.EHI / max(Z.EHI, na.rm = TRUE)

# Fit model
model <- S.CARdissimilarity(
  formula = formula,
  data = st_drop_geometry(chi_bg_sf),
  family = "poisson",
  W = W,
  Z = list(Z.EHI = Z.EHI),
  W.binary = TRUE,
  burnin = 20000,
  n.sample = 100000
)

# Extract alpha.min
alpha.min_val <- model$alpha.min[1]

# Extract posterior summary
model_summary <- summary(model)
posterior_names <- rownames(model_summary)
# Extract fixed effect summary from model$summary.results
posterior_summary <- model$summary.results

# Check if Z.EHI is among the rownames
if ("Z.EHI" %in% rownames(posterior_summary)) {
  z_summary <- posterior_summary["Z.EHI", c("Mean", "2.5%", "97.5%")]
  Z.EHI_mean <- z_summary["Mean"]
  Z.EHI_lower <- z_summary["2.5%"]
  Z.EHI_upper <- z_summary["97.5%"]
} else {
  Z.EHI_mean <- NA
  Z.EHI_lower <- NA
  Z.EHI_upper <- NA
}

# Count stepchanges
stepcount <- table(model$stepchange)
stepchanges <- if ("stepchange" %in% names(stepcount)) stepcount["stepchange"] else 0

# Final result row
sensitivity_row <- data.frame(
  threshold = threshold,
  alpha.min = model$summary.results["Z.EHI", "alpha.min"],
  Z.EHI_mean = Z.EHI_mean,
  Z.EHI_lower = Z.EHI_lower,
  Z.EHI_upper = Z.EHI_upper,
  stepchanges = stepchanges
)


print(sensitivity_row)

###############################################################
# Initialize results table
sensitivity_results <- data.frame(
  threshold = integer(),
  alpha.min = numeric(),
  Z.EHI_mean = numeric(),
  Z.EHI_lower = numeric(),
  Z.EHI_upper = numeric(),
  stepchanges = integer(),
  stringsAsFactors = FALSE
)

# Loop from threshold 2 to 6
for (threshold in 1:6) {
  message(paste("Running model for EHI >", threshold))
  
  # Create Z.EHI dissimilarity matrix
  high_ehi <- chi_bg_sf$EHI_decile > threshold
  Z_mat <- outer(high_ehi, high_ehi, FUN = function(x, y) as.numeric(x & y))
  Z_mat <- Z_mat / max(Z_mat, na.rm = TRUE)
  
  # Fit model
  model <- S.CARdissimilarity(
    formula = formula,
    data = st_drop_geometry(chi_bg_sf),
    family = "poisson",
    W = W,
    Z = list(Z.EHI = Z_mat),
    W.binary = TRUE,
    burnin = 20000,
    n.sample = 100000,
    thin= 10
  )
  
  # Extract posterior summary
  posterior_summary <- model$summary.results
  
  # Initialize values
  Z.EHI_mean <- NA
  Z.EHI_lower <- NA
  Z.EHI_upper <- NA
  alpha.min_val <- NA
  
  # Only extract if Z.EHI exists
  if ("Z.EHI" %in% rownames(posterior_summary)) {
    z_summary <- posterior_summary["Z.EHI", c("Mean", "2.5%", "97.5%")]
    Z.EHI_mean <- z_summary["Mean"]
    Z.EHI_lower <- z_summary["2.5%"]
    Z.EHI_upper <- z_summary["97.5%"]
    alpha.min_val <- posterior_summary["Z.EHI", "alpha.min"]
  }
  
  # Count stepchanges
  stepcount <- table(model$stepchange)
  stepchanges <- if ("stepchange" %in% names(stepcount)) stepcount["stepchange"] else 0
  
  # Store row
  sensitivity_row <- data.frame(
    threshold = threshold,
    alpha.min = alpha.min_val,
    Z.EHI_mean = Z.EHI_mean,
    Z.EHI_lower = Z.EHI_lower,
    Z.EHI_upper = Z.EHI_upper,
    stepchanges = stepchanges
  )
  
  # Append to results
  sensitivity_results <- rbind(sensitivity_results, sensitivity_row)
}

# View results
print(sensitivity_results)
