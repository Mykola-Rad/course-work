using Bogus;
using GenerateData.Models;

namespace GenerateData.Generators
{
    public class ReleaseInvoiceGenerator : IEntityGenerator<Invoice>
    {
        public List<Invoice> Generate(int count, GenerationContext context)
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
                invoice.Type = InvoiceType.Transfer;

                invoice.SenderStorageName = faker.PickRandom(context.AvailableStorageKeepers.Keys.ToList());
                invoice.SenderKeeperPhone = faker.PickRandom(context.AvailableStorageKeepers[invoice.SenderStorageName]);
                invoice.CounterpartyName = faker.PickRandom(context.AvailableCounterpartyNames);

                invoice.Date = DateOnly.FromDateTime(faker.Date.Past(2).ToUniversalTime());


                invoice.ReceiverKeeperPhone = null;
                invoice.ReceiverStorageName = null;

                generatedInvoices.Add(invoice);
            }

            context.AvailableInvoiceIds.AddRange(generatedInvoices.Select(i => i.InvoiceId));

            return generatedInvoices;
        }
    }
}
