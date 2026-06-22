// This library contains a list of concepts which designate insulin
// /ingredients/. These ingredients are used to filter the DrugStrength entries
// for the insulin /drugs/ defined in the InsulinDrugs library. Such a
// filtering is necessary because insulin drugs often contain multiple
// ingredients and some of those are not insulin variants.

library "InsulinIngredients"

include OMOPFunctions

include IndicateQiElements called E

code "insulin aspart":                             '35198096' from E.OMOPSV
code "insulin aspart protamine, human":            '1531601'  from E.OMOPSV
code "insulin aspart, human":                      '1567198'  from E.OMOPSV
code "insulin degludec":                           '35602717' from E.OMOPSV
code "insulin detemir":                            '1516976'  from E.OMOPSV
code "insulin glargine":                           '1502905'  from E.OMOPSV
code "insulin glulisine, human":                   '1544838'  from E.OMOPSV
code "insulin isophane":                           '46221581' from E.OMOPSV
code "insulin, prompt zinc, beef":                 '19090244' from E.OMOPSV
code "insulin, regular, human":                    '1596977'  from E.OMOPSV

concept "Insulin Ingredients": {
  "insulin aspart",
  "insulin aspart protamine, human",
  "insulin aspart, human",
  "insulin degludec",
  "insulin detemir",
  "insulin glargine",
  "insulin glulisine, human",
  "insulin isophane",
  "insulin, prompt zinc, beef",
  "insulin, regular, human"
}

define "Insulin Ingredient Concepts":
  ("Insulin Ingredients".codes) c return all OMOPFunctions.ToOMOPConcept(c)
