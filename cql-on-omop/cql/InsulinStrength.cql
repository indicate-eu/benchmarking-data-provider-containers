// This library contains functions for computing from DrugExposure entrie the
// effective amount of administered insulin in [IU].
//
// The computation is complicated by the fact that insulin drugs often contain
// multiple ingredients only some of which are insulin variants. Furthermore,
// the DrugStrength entries for the insulin ingredient use different units and
// need to be converted to [IU].

library "InsulinStrength" version '0.0.0'

using OMOP version 'v5.4'

include OMOPHelpers
include OMOPFunctions

// This function converts a mass-based insulin quantity into the
// corresponding quantity expressed in international units using the
// published conversion factor.
// Source: https://pmc.ncbi.nlm.nih.gov/articles/PMC6501531/
define function "Insulin in mg to IU"(quantity Quantity):
  Quantity{value: 28.7 * (convert quantity to 'mg').value, unit: '[IU]'}

// This function converts an insulin quantity that can be expressed in
// a number of different units into the corresponding quantity
// expressed in international units and an indication of whether the
// quantity describes an amount per volume or just an amount.
//
// The conversion are
// * x [hp_X]  -> 0 [IU], not per volume
// * x mg      -> y [IU], not per volume
// * x mg/ml   -> y [IU],     per volume
// * x mg/ml   -> y [IU],     per volume
// * x [IU]    -> x [IU], not per volume
// * x [IU]/ml -> y [IU],     per volume
// * otherwise -> null
//
// Note: amounts expressed as [U] or [U]/ml must already have been
// converted to [IU] or [IU]/ml when this function is called, for example
// by the registered DrugStrength -> Quantity conversion, because
// otherwise the CQL engine would choke on a quantity with unit '[U]'
// because the UCUM service does not recognize that unit.
define function "Insulin Amount in IU"(quantity Quantity):
  case
    // When the amount is specific as homeopathic dilution factor, we
    // assume that there is no biological effect.
    //
    // Note: [hp_X] is dimensionless so can't use
    //
    //   convert quantity to '[hp_X]'
    //
    // to detect it. The best we can do is look for the literal unit name.
    when quantity.unit = '[hp_X]' then
      {
        quantity:  0 '[IU]',
        perVolume: false
      }
    when (convert quantity to 'mg') is not null then
      { quantity: "Insulin in mg to IU"(quantity), perVolume: false }
    when (convert quantity to 'mg/ml') is not null then
      {
        quantity:  "Insulin in mg to IU"(quantity * 1 'ml'),
        perVolume: true
      }
    // The following cases will match for any unit of the form
    // <dimensionless> or <dimensionless>/<volume>. We assume that [IU]
    // is the only dimensionless unit that gets here.
    when (convert quantity to '[IU]') is not null then
      { quantity: quantity, perVolume: false }
    when (convert quantity to '[IU]/ml') is not null then
      {
        quantity:  Quantity{
                     value: (convert quantity to '1/ml').value,
                     unit:  '[IU]'
                   },
        perVolume: true
      }
    else
      null
  end

// This function extracts the insulin amount from a DrugStrength and
// returns a Quantity with unit [IU] and a Boolean which indicates
// whether the amount is per-volume.
define function "Insulin Strength in IU"(drugStrength DrugStrength):
  (1) _
    let quantity:     convert drugStrength to Quantity,
        quantityInIU: "Insulin Amount in IU"(quantity)
      return
      if quantityInIU is null then
        Message(null as Tuple{quantity Quantity, perVolume Boolean}, true, '400', 'Warning',
                'Unexpected unit in DrugStrength for ingredient '
                + drugStrength.ingredientConcept.conceptName
                + ' of drug ' + drugStrength.drugConcept.conceptName
                + ': ' + if quantity is null then 'null' else quantity.unit)
      else
        quantityInIU

// This function computes the total insulin amount in international
// units from the given DrugExposure.  Only ingredients in the given
// ingredient list are considered.  For each such ingredient, the insulin
// amount in international units is computed, these amounts are summed
// and multiplied by the quantity in the DrugExposure which designates
// either a volume-based amount in ml or an abstract amount.
define function "Insulin Exposure"(drugExposure OMOP.DrugExposure,
                                   ingredients  List<OMOP.Concept>):
  (1) _
    let strengths:        OMOPFunctions.DrugStrengthForDrug(drugExposure.drugConcept),
        insulinAmounts:   (strengths) s
                            where s.ingredientConcept in ingredients
                            return all "Insulin Strength in IU"(s),
        strengthQuantity: Sum((insulinAmounts) a return all a.quantity),
        perVolume:        (insulinAmounts) a return a.perVolume
      return case
               // If perVolume has more than one element, it must be
               // {false,true} which indicates a mixture of per-volume
               // strengths and abstract strengths.
               when Count(perVolume) > 1 then
                 Message(null as Quantity, true, '400', 'Error',
                         'Some strengths are given per-volume and some are not')
               when strengthQuantity is not null
                    and drugExposure.quantity is not null then
                 drugExposure.quantity * strengthQuantity
               else
                 Message(null as Quantity, true, '400', 'Error',
                         'Missing quantity in DrugExposure or failure to compute insulin amount from DrugStrengths')
             end
