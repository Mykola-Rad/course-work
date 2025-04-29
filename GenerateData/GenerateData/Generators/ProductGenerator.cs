using Bogus;
using GenerateData.Models;
using GenerateData.Utills;

namespace GenerateData.Generators
{
    public class ProductGenerator : IEntityGenerator<Product>
    {
        private const int maxProductNameLength = 100;
        private const decimal minProductPrice = 1.00m;
        private const decimal maxProductPrice = 5000.00m;
        public List<Product> Generate(int count, GenerationContext context)
        {
            if (!context.AvailableUnitCodes.Any())
                throw new InvalidOperationException(
                    "GenerationContext must contain AvailableUnitCodes " +
                    "before generating Products. Ensure ProductUnitGenerator runs first.");

            var productFaker = new Faker<Product>()
                .RuleFor(p => p.ProductName, f => DataGenerationUtils.GenerateValue(
                    faker => faker.Commerce.ProductName(), maxProductNameLength, f))
                .RuleFor(p => p.UnitCode, f => f.PickRandom(context.AvailableUnitCodes))
                .RuleFor(p => p.LastPrice, f => Math.Round(f.Random.Decimal(minProductPrice, maxProductPrice), 2));

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

            context.AvailableProductNames.AddRange(generatedProducts.Select(p => p.ProductName));

            return generatedProducts;
        }
    }
}
