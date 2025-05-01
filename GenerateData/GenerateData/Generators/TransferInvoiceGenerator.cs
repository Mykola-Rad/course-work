using Bogus;
using GenerateData.Data;
using GenerateData.Models;

namespace GenerateData.Generators
{
    public class TransferInvoiceGenerator : IEntityGenerator<Invoice>
    {
        private readonly AppDbContext _dbContext;
        private const string _invoiceType = "transfer";

        public TransferInvoiceGenerator(AppDbContext dbContext)
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

                invoice.ReceiverStorageName = faker.PickRandom(context.AvailableStorageKeepers
                    .Where(kvp => kvp.Value != null && kvp.Value.Any())
                    .Select(kvp => kvp.Key)
                    .ToList());
                invoice.ReceiverKeeperPhone = faker.PickRandom(context.AvailableStorageKeepers[invoice.ReceiverStorageName]);

                invoice.SenderStorageName = faker.PickRandom(context.AvailableStorageKeepers
                    .Where(kvp => kvp.Value != null && kvp.Value.Any() && kvp.Key != invoice.ReceiverStorageName)
                    .Select(kvp => kvp.Key)
                    .ToList());

                invoice.SenderKeeperPhone = faker.PickRandom(context.AvailableStorageKeepers[invoice.SenderStorageName]);
                invoice.Date = DateOnly.FromDateTime(faker.Date.Past(2).ToUniversalTime());

                
                invoice.CounterpartyName = null;

                generatedInvoices.Add(invoice);
            }

            return generatedInvoices;
        }
    }
}
