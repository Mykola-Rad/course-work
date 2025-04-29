using GenerateData.Models;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace GenerateData
{
    public class ProductUnitGenerator : IEntityGenerator<ProductUnit>
    {
        public List<ProductUnit> Generate(int count, GenerationContext context)
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

            if (context.AvailableUnitCodes == null)
            {
                context.AvailableUnitCodes = new List<string>();
            }

            context.AvailableUnitCodes.AddRange(predefinedUnits.Select(u => u.UnitCode));
            context.AvailableUnitCodes = context.AvailableUnitCodes.Distinct().ToList();

            return predefinedUnits;
        }
    }
}
