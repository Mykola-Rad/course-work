using GenerateData.Models;

namespace GenerateData.Generators
{
    public class ProductUnitGenerator : IEntityGenerator<ProductUnit>
    {
        public List<ProductUnit> Generate(GenerationContext context, int count = 100)
        {
            var predefinedUnits = new List<ProductUnit>
            {
                new ProductUnit { UnitCode = "kg", UnitName = "Kilogram" },
                new ProductUnit { UnitCode = "g", UnitName = "Gram" },
                new ProductUnit { UnitCode = "pcs", UnitName = "Pieces" },
                new ProductUnit { UnitCode = "l", UnitName = "Liter" },
                new ProductUnit { UnitCode = "ml", UnitName = "Milliliter" },
                new ProductUnit { UnitCode = "m", UnitName = "Meter" },
                new ProductUnit { UnitCode = "cm", UnitName = "Centimeter" },
                new ProductUnit { UnitCode = "m2", UnitName = "Square Meter" },
                new ProductUnit { UnitCode = "pack", UnitName = "Pack" },
                new ProductUnit { UnitCode = "box", UnitName = "Box" }
            };

            context.AvailableUnitCodes.AddRange(predefinedUnits.Select(u => u.UnitCode));

            return predefinedUnits;
        }
    }
}
