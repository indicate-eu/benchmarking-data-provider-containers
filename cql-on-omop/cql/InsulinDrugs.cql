// This file has been generated automatically from
// commit edaaf809a126b08f1c96ffd983434cb73973fa4f or https://github.com/indicate-eu/data-dictionary
// Concept set(s)
// * Insulin Aspart, Human (1 direct entries) [modified 2026-04-09]
// * Insulin Degludec (1 direct entries) [modified 2026-04-09]
// * Insulin Detemir (1 direct entries) [modified 2026-04-09]
// * Insulin Glargine (1 direct entries) [modified 2026-04-09]
// * Insulin Glulisine, Human (1 direct entries) [modified 2026-04-09]

// Do not edit

library "InsulinDrugs"

include IndicateQiElements called E

code "insulin aspart, human": '1567198' from E."OMOPSV Hierarchy"
code "insulin degludec": '35602717' from E."OMOPSV Hierarchy"
code "insulin detemir": '1516976' from E."OMOPSV Hierarchy"
code "insulin glargine": '1502905' from E."OMOPSV Hierarchy"
code "insulin glulisine, human": '1544838' from E."OMOPSV Hierarchy"

concept "Insulin Drugs": {
  "insulin aspart, human",
  "insulin degludec",
  "insulin detemir",
  "insulin glargine",
  "insulin glulisine, human"
}
