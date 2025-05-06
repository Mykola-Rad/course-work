namespace IMS.ViewModels
{
    public class HomeIndexViewModel
    {
        public bool ShowDashboard { get; set; }

        public DashboardViewModel? DashboardData { get; set; }

        public string WelcomeMessage { get; set; }
    }
}
