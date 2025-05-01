using GenerateData.Models;
using System;
using System.Collections.Generic;
using System.Linq;

namespace GenerateData.Generators
{
    public class ListEntryGenerator : IEntityGenerator<ListEntry>
    {
        private const int _minCount = 1;
        private const int _maxCount = 100;
        private const decimal _minPrice = 10;
        private const decimal _maxPrice = 1000;
        private readonly Random _random = new Random();

        public ListEntryGenerator()
        {
            _random = new Random();
        }

        public List<ListEntry> Generate(GenerationContext context, int count = 100)
        {
            if (!context.AvailableInvoiceIds.Any())
                throw new InvalidOperationException(
                    "GenerationContext must contain InvoiceId " +
                    "before generating ListEntries.");
            if (!context.AvailableProductNames.Any())
                throw new InvalidOperationException(
                    "GenerationContext must contain ProductNames " +
                    "before generating ListEntries.");

            var listEntries = new List<ListEntry>();
            int invoiceIdCount = context.AvailableInvoiceIds.Count;
            int productsPerInvoice = invoiceIdCount > 0 ? count / invoiceIdCount : 0;
            int remainingProducts = count % invoiceIdCount;

            var shuffledProductNames = context.AvailableProductNames.OrderBy(_ => _random.Next()).ToList();
            int productIndex = 0;

            foreach (var invoiceId in context.AvailableInvoiceIds)
            {
                int currentProductsCount = productsPerInvoice + (remainingProducts > 0 ? 1 : 0);
                remainingProducts--;

                var productsForInvoice = shuffledProductNames
                    .Skip(productIndex)
                    .Take(currentProductsCount)
                    .ToList();

                foreach (var productName in productsForInvoice)
                {
                    listEntries.Add(new ListEntry
                    {
                        InvoiceId = invoiceId,
                        ProductName = productName,
                        Count = Math.Round((decimal)_random.Next(_minCount * 100, _maxCount * 100) / 100, 2),
                        Price = Math.Round(_minPrice + (_maxPrice - _minPrice) * (decimal)_random.NextDouble(), 2)
                    });
                }

                productIndex += currentProductsCount;
                if (productIndex >= shuffledProductNames.Count)
                {
                    shuffledProductNames = context.AvailableProductNames.OrderBy(_ => _random.Next()).ToList();
                    productIndex = 0;
                }
            }

            return listEntries;
        }
    }
}