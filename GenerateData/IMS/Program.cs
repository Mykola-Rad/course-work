using IMS.Data;
using IMS.Models;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.EntityFrameworkCore;
using Serilog;
using Serilog.Events;

namespace IMS
{
    public class Program
    {
        public static void Main(string[] args)
        {
            Log.Logger = new LoggerConfiguration()
                .MinimumLevel.Override("Microsoft", LogEventLevel.Warning)
                .Enrich.FromLogContext()
                .WriteTo.Console()
                .WriteTo.File(
                    "Logs/ims_log_.txt",
                    rollingInterval: RollingInterval.Day,
                    retainedFileCountLimit: 7,
                    outputTemplate: "{Timestamp:yyyy-MM-dd HH:mm:ss.fff zzz} [{Level:u3}] ({SourceContext}) {Message:lj}{NewLine}{Exception}")
                .CreateBootstrapLogger();

            try
            {
                var builder = WebApplication.CreateBuilder(args);

                builder.Host.UseSerilog((context, services, configuration) => configuration
                    .ReadFrom.Configuration(context.Configuration)
                    .ReadFrom.Services(services)
                    .Enrich.FromLogContext()
                    .MinimumLevel.Information()
                    .MinimumLevel.Override("Microsoft", LogEventLevel.Warning) 
                    .MinimumLevel.Override("Microsoft.AspNetCore", LogEventLevel.Warning) 
                    .MinimumLevel.Override("Microsoft.EntityFrameworkCore.Database.Command", LogEventLevel.Warning)
                    .MinimumLevel.Override("Microsoft.Hosting.Lifetime", LogEventLevel.Information) 
                    .WriteTo.Console()
                    .WriteTo.File(
                        "Logs/ims_log_.txt",
                        rollingInterval: RollingInterval.Day,
                        retainedFileCountLimit: 7,
                        outputTemplate: "{Timestamp:yyyy-MM-dd HH:mm:ss.fff zzz} [{Level:u3}] ({SourceContext}) {Message:lj}{NewLine}{Exception}")
                );

                // Add services to the container.
                builder.Services.AddControllersWithViews();

                builder.Services.AddDbContext<AppDbContext>(options =>
                    options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection"),
                    o =>
                    {
                        o.MapEnum<UserRole>("user_role");
                        o.MapEnum<InvoiceStatus>("invoice_status");
                        o.MapEnum<InvoiceType>("invoice_type");
                    }));

                builder.Services.AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme)
                    .AddCookie(options =>
                    {
                        options.LoginPath = "/Account/Login";

                        options.AccessDeniedPath = "/Account/AccessDenied";

                        options.ExpireTimeSpan = TimeSpan.FromMinutes(60);

                        options.SlidingExpiration = true;
                    });

                builder.Services.AddAuthorization(options =>
                {
                    options.AddPolicy("RequireOwnerRole", policy =>
                        policy.RequireRole("owner"));

                    options.AddPolicy("RequireManagerRole", policy =>
                        policy.RequireRole("manager", "owner"));

                    options.AddPolicy("RequireStorageKeeperRole", policy =>
                        policy.RequireRole("storage_keeper", "manager", "owner"));
                });

                var app = builder.Build();

                app.UseSerilogRequestLogging();

                // Configure the HTTP request pipeline.
                if (!app.Environment.IsDevelopment())
                {
                    app.UseExceptionHandler("/Home/Error");
                    // The default HSTS value is 30 days. You may want to change this for production scenarios, see https://aka.ms/aspnetcore-hsts.
                    app.UseHsts();
                }

                app.UseHttpsRedirection();
                app.UseStaticFiles();

                app.UseRouting();

                app.UseAuthentication();
                app.UseAuthorization();

                app.MapControllerRoute(
                    name: "default",
                    pattern: "{controller=Home}/{action=Index}/{id?}");

                app.Run();
            }
            catch (Exception ex)
            {
                Log.Fatal(ex, "Application terminated unexpectedly"); 
            }
            finally
            {
                Log.CloseAndFlush(); 
            }
        }
    }
}
