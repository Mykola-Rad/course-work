using GenerateData.Data;
using GenerateData.Generators;
using GenerateData.Models;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using System;
using System.Threading.Tasks;

namespace GenerateData
{
    internal class Program
    {
        private const string connStr = "Host=localhost;Database=CourseWork;Username=postgres;Password=1709";

        static async Task Main(string[] args)
        {
            using IHost host = Host.CreateDefaultBuilder(args)
                .ConfigureServices((hostContext, services) =>
                {
                    services.AddDbContext<AppDbContext>(options =>
                        options.UseNpgsql(connStr));
                    services.AddTransient<DBSeeder>();
                    services.AddLogging(builder =>
                    {
                        builder.AddConsole();
                        builder.SetMinimumLevel(LogLevel.Information);
                    });
                })
                .Build();

            var serviceProvider = host.Services;

            try
            {
                var dbSeeder = serviceProvider.GetRequiredService<DBSeeder>();
                await dbSeeder.SeedDatabaseAsync();
            }
            catch (Exception ex)
            {
                var logger = serviceProvider.GetRequiredService<ILogger<Program>>();
                logger.LogError(ex, "Під час запуску сідера сталася помилка.");
            }
            finally
            {
                await host.StopAsync();
            }
        }
    }
}