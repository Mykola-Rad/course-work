using Bogus;
using GenerateData.Models;

namespace GenerateData.Generators
{
    public class ProductGenerator : IEntityGenerator<Product>
    {
        public List<Product> Generate(int count, GenerationContext context)
        {
            if (context.AvailableUnitCodes == null || !context.AvailableUnitCodes.Any())
            {
                throw new InvalidOperationException("GenerationContext must contain AvailableUnitCodes before generating Products. Ensure ProductUnitGenerator runs first.");
            }

            var productFaker = new Faker<Product>()
                .RuleFor(p => p.ProductName, f => f.Commerce.ProductName())
                .RuleFor(p => p.UnitCode, f => f.PickRandom(context.AvailableUnitCodes))
                .RuleFor(p => p.LastPrice, f => Math.Round(f.Random.Decimal(1.00m, 5000.00m), 2));

            var generatedProducts = new List<Product>();
            var uniqueNames = new HashSet<string>();

            while (generatedProducts.Count < count)
            {
                var product = productFaker.Generate();

                string baseProductName = product.ProductName;
                string uniqueProductName = baseProductName;

                if (uniqueNames.Add(uniqueProductName))
                    product.ProductName = uniqueProductName;
                else
                {
                    int index = 1;
                    do
                        uniqueProductName = $"{baseProductName} {index++}";
                    while (!uniqueNames.Add(uniqueProductName));

                    product.ProductName = uniqueProductName;
                }

                generatedProducts.Add(product);
            }

            if (context.GeneratedProductNames == null)
                context.GeneratedProductNames = new List<string>();

            context.GeneratedProductNames.AddRange(generatedProducts.Select(p => p.ProductName));

            return generatedProducts;
        }
    }
}
