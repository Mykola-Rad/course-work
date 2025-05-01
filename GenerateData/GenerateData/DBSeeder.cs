using GenerateData.Data;
using GenerateData.Generators;
using GenerateData.Models;  
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging; 

namespace GenerateData
{
    public class DBSeeder
    {
        private const string _ownerRole = "owner";
        private const string _managerRole = "manager";
        private const string _keeperRole = "storage_keeper";

        private readonly AppDbContext _context;
        private readonly ILogger<DBSeeder> _logger;
        public int StorageCount { get; set; } = 50;
        public int OwnersCount { get; set; } = 1;
        public int ManagersCount { get; set; } = 50;
        public int KeeperCount { get; set; } = 200;
        public int ProductCount { get; set; } = 500;
        public int CounterpartyCount { get; set; } = 100;
        public int InvoiceCount { get; set; } = 1000;
        public int ListEntryPerInvoice { get; set; } = 5;
        public int ProductsPerStorageCount { get; set; } = 15;

        public DBSeeder(AppDbContext context, ILogger<DBSeeder> logger)
        {
            _context = context;
            _logger = logger;
        }

        public async Task SeedDatabaseAsync()
        {
            _logger.LogInformation("Починається процес очищення та заповнення бази даних...");

            await ClearDatabaseAsync(useTruncate: true);

            await SeedDataAsync();

            _logger.LogInformation("Процес очищення та заповнення бази даних завершено.");
        }

        private async Task SeedDataAsync()
        {
            _logger.LogInformation("Заповнення бази даних...");
            var generationContext = new GenerationContext();

            var productUnitGen = new ProductUnitGenerator();
            var storageGen = new StorageGenerator();
            var userGen = new UserGenerator();
            var counterpartyGen = new CounterpartyGenerator(_context);
            var productGen = new ProductGenerator();
            var keeperGen = new StorageKeeperGenerator();
            var supplyInvoiceGen = new SupplyInvoiceGenerator(_context);
            var transferInvoiceGen = new TransferInvoiceGenerator(_context);
            var releaseInvoiceGen = new ReleaseInvoiceGenerator(_context);
            var listEntryGen = new ListEntryGenerator();         
            var storageProductGen = new StorageProductGenerator();
            var rolesGenerator = new CounterpartyRoleGenerator();

            try 
            {
                _logger.LogDebug("Генерація ProductUnits...");
                var units = productUnitGen.Generate(generationContext);
                _context.ProductUnits.AddRange(units);
                await _context.SaveChangesAsync();

                _logger.LogInformation($"Згенеровано та збережено: {units.Count} ProductUnits.");

                _logger.LogDebug("Генерація Storages...");
                var storages = storageGen.Generate(generationContext, StorageCount);
                _context.Storages.AddRange(storages);
                await _context.SaveChangesAsync();

                var roles = rolesGenerator.Generate(generationContext);
                _context.CounterpartyRoles.AddRange(roles);
                await _context.SaveChangesAsync();

                _logger.LogDebug("Генерація Counterparties...");
                var counterparties = counterpartyGen.Generate(generationContext, CounterpartyCount);
                _context.Counterparties.AddRange(counterparties);
                await _context.SaveChangesAsync();

                _logger.LogDebug("Генерація Users (включаючи комірників)...");

                userGen.Role = _ownerRole;
                var owners = userGen.Generate(generationContext, OwnersCount);
                owners.Add(new User
                {
                    Username = "admin",
                    PasswordHash = BCrypt.Net.BCrypt.HashPassword("admin"),
                    Role = _ownerRole
                });
                userGen.Role = _managerRole;
                var managers = userGen.Generate(generationContext, ManagersCount);

                userGen.Role = _keeperRole;
                var keeperUsers = userGen.Generate(generationContext, KeeperCount);

                await InsertUsersDirectlyAsync(owners);
                await InsertUsersDirectlyAsync(managers);
                await InsertUsersDirectlyAsync(keeperUsers);
                await _context.SaveChangesAsync();

                generationContext.AvailableUserIds.AddRange(_context.Users
                    .Where(u => u.Role == _keeperRole)
                    .Select(u => u.UserId));

                _logger.LogInformation($"Згенеровано та збережено: {storages.Count} Storages, " +
                    $"{counterparties.Count} Counterparties, " +
                    $"{keeperUsers.Count + managers.Count + owners.Count} Users.");

                _logger.LogDebug("Генерація Products...");
                var products = productGen.Generate(generationContext, ProductCount);
                _context.Products.AddRange(products);
                await _context.SaveChangesAsync();

                _logger.LogDebug("Генерація StorageKeepers...");
                var keepers = keeperGen.Generate(generationContext, KeeperCount);
                _context.StorageKeepers.AddRange(keepers);
                await _context.SaveChangesAsync();

                _logger.LogInformation($"Згенеровано та збережено: {products.Count} Products, {keepers.Count} StorageKeepers.");

                _logger.LogDebug("Генерація Invoices...");
                int supplyCount = (int)(InvoiceCount * 0.4);
                int transferCount = (int)(InvoiceCount * 0.3);
                int releaseCount = InvoiceCount - supplyCount - transferCount;

                var supplyInvoices = supplyInvoiceGen.Generate(generationContext, supplyCount);
                var transferInvoices = transferInvoiceGen.Generate(generationContext, transferCount);
                var releaseInvoices = releaseInvoiceGen.Generate(generationContext, releaseCount);

                var allInvoices = supplyInvoices.Concat(transferInvoices).Concat(releaseInvoices).ToList();
                await InsertInvoicesDirectlyAsync(allInvoices);
                await _context.SaveChangesAsync();
                generationContext.AvailableInvoiceIds.AddRange(_context.Invoices
                    .Select(i => i.InvoiceId));

                _logger.LogInformation($"Згенеровано та збережено: {allInvoices.Count} Invoices.");

                _logger.LogDebug("Генерація StorageProducts...");
                var storageProducts = storageProductGen.Generate(generationContext, ProductsPerStorageCount * StorageCount);
                _context.StorageProducts.AddRange(storageProducts);
                await _context.SaveChangesAsync();

                _logger.LogDebug("Генерація ListEntries...");
                var listEntries = listEntryGen.Generate(generationContext, InvoiceCount * ListEntryPerInvoice);
                _context.ListEntries.AddRange(listEntries);
                await _context.SaveChangesAsync();

                _logger.LogInformation($"Згенеровано та збережено: {listEntries.Count} ListEntries, {storageProducts.Count} StorageProducts.");

                _logger.LogInformation("Заповнення бази даних успішно завершено.");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Помилка під час заповнення бази даних.");
                throw;
            }
        }

        public async Task ClearDatabaseAsync(bool useTruncate = false)
        {
            _logger.LogWarning("Початок очищення даних з бази...");

            if (useTruncate)
                await ClearDatabaseWithTruncateAsync();
            else
                await ClearDatabaseWithRemoveRangeAsync();

            _logger.LogInformation("Очищення даних завершено.");
        }


        private async Task ClearDatabaseWithRemoveRangeAsync()
        {
            _logger.LogDebug("Очищення за допомогою RemoveRange...");

           
            _context.ListEntries.RemoveRange(_context.ListEntries);
            _context.StorageProducts.RemoveRange(_context.StorageProducts);
            await _context.SaveChangesAsync();
            _logger.LogDebug("ListEntries, StorageProducts видалено.");

            _context.Invoices.RemoveRange(_context.Invoices);
            await _context.SaveChangesAsync();
            _logger.LogDebug("Invoices видалено.");

            _context.StorageKeepers.RemoveRange(_context.StorageKeepers);
            await _context.SaveChangesAsync();
            _logger.LogDebug("StorageKeepers видалено.");

            _context.Set<Dictionary<string, object>>("CounterpartyRoleMap").RemoveRange(_context.Set<Dictionary<string, object>>("CounterpartyRoleMap"));
            _context.CounterpartyRoles.RemoveRange(_context.CounterpartyRoles);
            await _context.SaveChangesAsync();
            _logger.LogDebug("CounterpartyRoleMap та CounterpartyRoles видалено.");

            _context.Products.RemoveRange(_context.Products);
            await _context.SaveChangesAsync();
            _logger.LogDebug("Products видалено.");

            _context.ProductUnits.RemoveRange(_context.ProductUnits);
            await _context.SaveChangesAsync();
            _logger.LogDebug("ProductUnits видалено.");


            _context.Users.RemoveRange(_context.Users);
            await _context.SaveChangesAsync();
            _logger.LogDebug("Users видалено.");

            _context.Counterparties.RemoveRange(_context.Counterparties);
            _context.Storages.RemoveRange(_context.Storages);
            await _context.SaveChangesAsync();
            _logger.LogDebug("Counterparties, Storages видалено.");

        }

        private async Task ClearDatabaseWithTruncateAsync()
        {
            _logger.LogWarning("Очищення за допомогою TRUNCATE... Це небезпечна операція!");

            string sql = @"
            TRUNCATE TABLE
                public.""list_entry"",
                public.""storage_product"",
                public.""invoice"",
                public.""storage_keeper"",
                public.""counterparty_role_map"", 
                public.""counterparty_role"",
                public.""product"",
                public.""product_units"",
                public.""user"",
                public.""counterparty"",
                public.""storage""
            RESTART IDENTITY CASCADE;";

            try
            {
                await _context.Database.ExecuteSqlRawAsync(sql);
                _logger.LogInformation("Таблиці успішно очищено за допомогою TRUNCATE.");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Помилка під час виконання TRUNCATE.");
                throw;
            }
        }

        private async Task InsertUsersDirectlyAsync(List<User> users)
        {
            if (users == null || !users.Any())
            {
                return;
            }

            var sql = @"
                INSERT INTO public.""user"" (username, password_hash, role)
                VALUES {0}";

            var userValues = new List<string>();
            foreach (var user in users)
                userValues.Add($"('{user.Username}', '{user.PasswordHash}', '{user.Role}')");

            var values = string.Join(",", userValues);
            var fullSql = string.Format(sql, values);

            try
            {
                await _context.Database.ExecuteSqlRawAsync(fullSql);
                _logger.LogInformation($"Успішно вставлено {users.Count} користувачів через прямий SQL.");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Помилка під час вставки користувачів через прямий SQL.");
                throw;
            }
        }

        private async Task InsertInvoicesDirectlyAsync(List<Invoice> invoices)
        {
            if (invoices == null || !invoices.Any())
                return;


            var sql = @"
                INSERT INTO public.""invoice"" (counterparty_name, sender_keeper_phone, receiver_keeper_phone, sender_storage_name, receiver_storage_name, type, date)
                VALUES {0}";

            var invoiceValues = new List<string>();
            foreach (var invoice in invoices)
            {
                invoiceValues.Add($"({(invoice.CounterpartyName == null ? "NULL" : $"'{invoice.CounterpartyName.Replace("'", "''")}'")}, " +
                                    $"{(invoice.SenderKeeperPhone == null ? "NULL" : $"'{invoice.SenderKeeperPhone.Replace("'", "''")}'")}, " +
                                    $"{(invoice.ReceiverKeeperPhone == null ? "NULL" : $"'{invoice.ReceiverKeeperPhone.Replace("'", "''")}'")}, " +
                                    $"{(invoice.SenderStorageName == null ? "NULL" : $"'{invoice.SenderStorageName.Replace("'", "''")}'")}, " +
                                    $"{(invoice.ReceiverStorageName == null ? "NULL" : $"'{invoice.ReceiverStorageName.Replace("'", "''")}'")}, " +
                                    $"'{invoice.Type}', '{invoice.Date.ToString("yyyy-MM-dd")}')");
            }

            var values = string.Join(",", invoiceValues);
            var fullSql = string.Format(sql, values);

            try
            {
                await _context.Database.ExecuteSqlRawAsync(fullSql);
                _logger.LogInformation($"Успішно вставлено {invoices.Count} рахунків через прямий SQL.");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Помилка під час вставки рахунків через прямий SQL.");
                throw;
            }
        }
    }
}
