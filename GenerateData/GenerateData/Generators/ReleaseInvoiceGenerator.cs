using Bogus;
using GenerateData.Data;
using GenerateData.Models;
using Microsoft.EntityFrameworkCore;

namespace GenerateData.Generators
{
    public class ReleaseInvoiceGenerator : IEntityGenerator<Invoice>
    {
        private readonly AppDbContext _dbContext;
        private const string _invoiceType = "release";

        public ReleaseInvoiceGenerator(AppDbContext dbContext)
        {
            _dbContext = dbContext;
        }
        public List<Invoice> Generate(GenerationContext context, int count = 100)
        {
            if (!context.AvailableStorageKeepers.Keys.Any())
                throw new InvalidOperationException("Need available Storage names for supply invoices.");
            if (!context.AvailableStorageKeepers.Values.Any())
                throw new InvalidOperationException("Need available Storage keepers for supply invoices.");
            if (!context.AvailableCounterpartyNames.Any())
                throw new InvalidOperationException("Need available Counterparty names for supply invoices.");

            var generatedInvoices = new List<Invoice>();
            var faker = new Faker();
            for (int i = 0; i < count; i++)
            {
                var invoice = new Invoice();
                invoice.Type = _invoiceType;

                invoice.SenderStorageName = faker.PickRandom(context.AvailableStorageKeepers
                    .Where(kvp => kvp.Value != null && kvp.Value.Any())
                    .Select(kvp => kvp.Key)
                    .ToList());
                invoice.SenderKeeperPhone = faker.PickRandom(context.AvailableStorageKeepers[invoice.SenderStorageName]);
                invoice.CounterpartyName = faker.PickRandom(context.AvailableCounterpartyNames);

                invoice.Date = DateOnly.FromDateTime(faker.Date.Past(2).ToUniversalTime());


                invoice.ReceiverKeeperPhone = null;
                invoice.ReceiverStorageName = null;

                generatedInvoices.Add(invoice);
            }

            return generatedInvoices;
        }
    }
}
